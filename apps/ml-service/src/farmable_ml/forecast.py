"""Cutoff-aware simple forecasts and walk-forward selection.

This layer deliberately accepts observations in one declared price basis. Nominal
input is NOT silently relabelled as 2025 rand. Real-price normalization belongs
upstream and must reconstruct the information available at each origin.
"""

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass
from datetime import date
from decimal import ROUND_HALF_EVEN, Context, Decimal, localcontext

from farmable_ml.data import Crop, ObservationPolicy, PriceObservation, observations_before

D = Decimal
QUANTILES = (D("0.1"), D("0.5"), D("0.9"))


class InsufficientHistory(ValueError):
    """A method cannot forecast this origin under its declared history policy."""


def shift_month(month: date, offset: int) -> date:
    if month.day != 1:
        raise ValueError("month must be its first day")
    year, index = divmod(month.year * 12 + month.month - 1 + offset, 12)
    return date(year, index + 1, 1)


def quantile(values: Sequence[Decimal], probability: Decimal) -> Decimal:
    """Linear interpolation between ordered observations (including endpoints)."""
    if not values or any(not value.is_finite() for value in values):
        raise ValueError("quantiles require nonempty finite values")
    if not probability.is_finite() or not 0 <= probability <= 1:
        raise ValueError("probability must be in [0, 1]")
    ordered = sorted(values)
    with localcontext(Context(prec=28, rounding=ROUND_HALF_EVEN)):
        position = probability * (len(ordered) - 1)
        lower = int(position)
        upper = min(lower + 1, len(ordered) - 1)
        return ordered[lower] + (position - lower) * (ordered[upper] - ordered[lower])


@dataclass(frozen=True)
class Forecast:
    crop: Crop
    origin: date
    target: date
    method: str
    p10: Decimal
    p50: Decimal
    p90: Decimal

    def __post_init__(self) -> None:
        if self.origin.day != 1 or self.target.day != 1 or self.target < self.origin:
            raise ValueError("forecast months must start on day one; target cannot precede origin")
        if any(not value.is_finite() or value <= 0 for value in self.values):
            raise ValueError("forecast prices must be finite and positive")
        if tuple(sorted(self.values)) != self.values:
            raise ValueError("forecast quantiles must be ordered")

    @property
    def values(self) -> tuple[Decimal, Decimal, Decimal]:
        return self.p10, self.p50, self.p90


def _history(
    records: tuple[PriceObservation, ...],
    crop: Crop,
    market: str,
    origin: date,
    *,
    policy: ObservationPolicy = ObservationPolicy.PUBLICATION,
) -> tuple[PriceObservation, ...]:
    history = tuple(
        row
        for row in observations_before(records, origin, policy=policy)
        if row.crop == crop and row.market == market
    )
    if len({row.observation_month for row in history}) != len(history):
        raise ValueError("duplicate historical months; resolve vintages before forecasting")
    return history


def historical_range(
    records: tuple[PriceObservation, ...],
    *,
    crop: Crop,
    market: str,
    origin: date,
    target: date,
    minimum_years: int = 3,
    policy: ObservationPolicy = ObservationPolicy.PUBLICATION,
) -> Forecast:
    if minimum_years < 1:
        raise ValueError("minimum_years must be positive")
    values = [
        row.price_rand_per_kg
        for row in _history(records, crop, market, origin, policy=policy)
        if row.observation_month.month == target.month
    ]
    if len(values) < minimum_years:
        raise InsufficientHistory("insufficient target-month observations")
    return Forecast(
        crop, origin, target, "historical_range", *(quantile(values, q) for q in QUANTILES)
    )


def same_month_last_year(
    records: tuple[PriceObservation, ...],
    *,
    crop: Crop,
    market: str,
    origin: date,
    target: date,
    policy: ObservationPolicy = ObservationPolicy.PUBLICATION,
) -> Forecast:
    previous = shift_month(target, -12)
    for row in _history(records, crop, market, origin, policy=policy):
        if row.observation_month == previous:
            value = row.price_rand_per_kg
            return Forecast(crop, origin, target, "same_month_last_year", value, value, value)
    raise InsufficientHistory("last-year target is unavailable at origin")


def pinball_loss(forecast: Forecast, actual: Decimal) -> Decimal:
    if not actual.is_finite() or actual <= 0:
        raise ValueError("actual price must be finite and positive")
    with localcontext(Context(prec=28, rounding=ROUND_HALF_EVEN)):
        losses = []
        for q, prediction in zip(QUANTILES, forecast.values, strict=True):
            error = actual - prediction
            losses.append(max(q * error, (q - 1) * error))
        return sum(losses, D(0)) / 3


# Adapters close over crop/market/hyperparameters. Selection supplies only history
# available at that fold's origin, even to a third-party model implementation.
Predictor = Callable[[tuple[PriceObservation, ...], date, date], Forecast]


@dataclass(frozen=True)
class ValidationFold:
    origin: date
    target: date
    actual: Decimal
    losses: tuple[tuple[str, Decimal | None], ...]


@dataclass(frozen=True)
class Selection:
    winner: str
    scores: tuple[tuple[str, Decimal | None], ...]
    folds: tuple[ValidationFold, ...]


class SelectionUnavailable(InsufficientHistory):
    """Retain evaluated folds when no method supports the common targets."""

    def __init__(
        self,
        message: str,
        *,
        folds: tuple[ValidationFold, ...] = (),
        scores: tuple[tuple[str, Decimal | None], ...] = (),
    ):
        super().__init__(message)
        self.folds, self.scores = folds, scores


def select_method(
    records: tuple[PriceObservation, ...],
    *,
    crop: Crop,
    market: str,
    cutoff: date,
    horizon_months: int,
    methods: Mapping[str, Predictor],
    tie_order: Sequence[str],
    validation_months: int = 36,
    minimum_folds: int = 12,
    policy: ObservationPolicy = ObservationPolicy.PUBLICATION,
) -> Selection:
    """Score all methods on identical known targets, rebuilding each old origin.

    Insufficient history on ANY common target disqualifies that method, instead
    of rewarding dropped difficult targets. Other errors propagate. No fallback
    or full-period winner is silently substituted into historical decisions.
    """
    if horizon_months < 0 or minimum_folds < 1 or validation_months < minimum_folds:
        raise ValueError("invalid horizon or validation window")
    if not methods or len(tie_order) != len(methods) or set(tie_order) != set(methods):
        raise ValueError("tie_order must list every method exactly once")
    earliest = shift_month(cutoff, -validation_months)
    targets = sorted(
        (
            row
            for row in _history(records, crop, market, cutoff, policy=policy)
            if earliest <= row.observation_month < cutoff
        ),
        key=lambda row: row.observation_month,
    )
    if len(targets) < minimum_folds:
        raise SelectionUnavailable("insufficient available validation targets")
    folds = []
    totals: dict[str, Decimal | None] = dict.fromkeys(tie_order, D(0))
    for row in targets:
        origin = shift_month(row.observation_month, -horizon_months)
        history = observations_before(records, origin, policy=policy)
        losses: list[tuple[str, Decimal | None]] = []
        for name in tie_order:
            try:
                prediction = methods[name](history, origin, row.observation_month)
                if (prediction.crop, prediction.origin, prediction.target) != (
                    crop,
                    origin,
                    row.observation_month,
                ):
                    raise ValueError("predictor returned a mismatched crop/origin/target")
                loss = pinball_loss(prediction, row.price_rand_per_kg)
                losses.append((name, loss))
                total = totals[name]
                if total is not None:
                    totals[name] = total + loss
            except InsufficientHistory:
                totals[name] = None
                losses.append((name, None))
        folds.append(
            ValidationFold(origin, row.observation_month, row.price_rand_per_kg, tuple(losses))
        )
    scores = tuple(
        (name, None if total is None else total / len(folds)) for name, total in totals.items()
    )
    supported = [
        (score, index, name) for index, (name, score) in enumerate(scores) if score is not None
    ]
    if not supported:
        raise SelectionUnavailable(
            "no method supports all common validation targets", folds=tuple(folds), scores=scores
        )
    return Selection(min(supported)[2], scores, tuple(folds))
