"""Version-1 retrospective simulation components, not a real-data entry point.

These components implement the rules in ml/backtest/PROTOCOL.md. Calling them
does not establish source acceptance or protocol registration. A real-data
runner must enforce those gates before construction; development tests use
fabricated observations only. No files, database connections or network calls
are made here.
"""

from collections.abc import Callable, Mapping, Sequence
from dataclasses import dataclass, replace
from datetime import date
from decimal import ROUND_HALF_EVEN, Context, Decimal, localcontext
from types import MappingProxyType

from farmable_ml.challenger import lightgbm_quantiles
from farmable_ml.cpi import CpiSeries
from farmable_ml.data import Crop, ObservationPolicy, PriceObservation
from farmable_ml.decision import Decision
from farmable_ml.forecast import (
    Forecast,
    InsufficientHistory,
    Predictor,
    Selection,
    SelectionUnavailable,
    ValidationFold,
    historical_range,
    same_month_last_year,
    select_method,
    shift_month,
)
from farmable_ml.money import gross_margin
from farmable_ml.reports import HISTORICAL_MONTHS

D = Decimal
POLICY = ObservationPolicy.RETROSPECTIVE
ORIGINAL_PROTOCOL_SHA256 = "a090d4e9d517b2b8c0d9d5009b5b9c5c9a827386e178f6e265052270923ea99d"
PROTOCOL_SHA256 = "f16d5090a2aa6560082ba2e9d582b39076223cb44811b1f42047d8d392378e3c"
LAST_REALIZED_MONTH = date(2024, 12, 1)


@dataclass(frozen=True)
class ProductionAssumptions:
    planting_months: frozenset[int]
    harvest_months: int
    yield_kg_per_ha: Decimal
    cost_2025_rand_per_ha: Decimal
    marketing_rate: Decimal

    def margin(self, price_2025: Decimal) -> Decimal:
        """Deduct marketing from revenue, not from the cost subtotal or margin."""
        with localcontext(Context(prec=28, rounding=ROUND_HALF_EVEN)):
            return gross_margin(
                price_rand_per_kg=price_2025 * (1 - self.marketing_rate),
                yield_kg_per_ha=self.yield_kg_per_ha,
                cost_rand_per_ha=self.cost_2025_rand_per_ha,
                occupied_months=D(self.harvest_months),
            )


# Frozen scenario inputs, NOT claims about historical publication or local farm
# conditions. A dated protocol amendment is required before changing these.
ASSUMPTIONS = MappingProxyType(
    {
        Crop.BUTTERNUT: ProductionAssumptions(
            frozenset({9, 10, 11}), 5, D(22500), D("60756.87"), D("0.125")
        ),
        Crop.CABBAGE: ProductionAssumptions(
            frozenset({1, 2, 3, 4, 5, 11, 12}), 3, D(75000), D("115183.85"), D("0.125")
        ),
        Crop.CARROTS: ProductionAssumptions(
            frozenset({1, 2, 3, 8, 9, 10}), 4, D(50000), D("68312.94"), D("0.125")
        ),
        Crop.GREEN_BEANS: ProductionAssumptions(
            frozenset({1, 9, 10, 11, 12}), 3, D(10000), D("136357.03"), D("0.125")
        ),
        Crop.ONIONS: ProductionAssumptions(
            frozenset({2, 3}), 7, D(42500), D("108783.41"), D("0.125")
        ),
        Crop.POTATOES: ProductionAssumptions(
            frozenset({1, 2, 7, 8, 9, 10}), 5, D(45000), D("181097.86"), D("0.125")
        ),
        Crop.SPINACH: ProductionAssumptions(
            frozenset({1, 2, 3, 4, 8, 9, 10, 11, 12}), 3, D(20000), D("167412.66"), D("0.125")
        ),
        Crop.TOMATOES: ProductionAssumptions(
            frozenset({8, 9, 10, 11}), 3, D(62500), D("168968.20"), D(0)
        ),
    }
)


@dataclass(frozen=True)
class ForecastAudit:
    crop: Crop
    origin: date
    target: date
    selected: Forecast | None
    selection: Selection | None
    diagnostic: Forecast | None
    skip_reason: str | None
    diagnostic_failure: str | None
    failed_selection_folds: tuple[ValidationFold, ...] = ()
    failed_selection_scores: tuple[tuple[str, Decimal | None], ...] = ()


@dataclass(frozen=True)
class FrozenChoice:
    origin: date
    recommended: Crop | None
    forecasts: tuple[ForecastAudit, ...]
    skip_reason: str | None


@dataclass(frozen=True)
class Simulation:
    choices: tuple[FrozenChoice, ...]
    decisions: tuple[Decision, ...]


def choose(
    forecasts: tuple[ForecastAudit, ...],
    *,
    origin: date,
    assumptions: Mapping[Crop, ProductionAssumptions] = ASSUMPTIONS,
) -> FrozenChoice:
    """Freeze a choice with no access to realized prices, even if all margins lose."""
    eligible = {
        crop for crop, inputs in assumptions.items() if origin.month in inputs.planting_months
    }
    if origin.day != 1:
        raise ValueError("planting origin must use day one")
    if len(forecasts) != len(eligible) or {row.crop for row in forecasts} != eligible:
        raise ValueError("exactly one forecast audit per in-season crop is required")
    ordered = tuple(sorted(forecasts, key=lambda row: row.crop))
    for row in ordered:
        expected_target = shift_month(origin, assumptions[row.crop].harvest_months)
        if row.origin != origin or row.target != expected_target:
            raise ValueError("forecast audit does not match the registered crop horizon")
        if row.selected is not None:
            if (row.selected.crop, row.selected.origin, row.selected.target) != (
                row.crop,
                origin,
                expected_target,
            ):
                raise ValueError("forecast does not match its audit identity")
            if row.skip_reason is not None:
                raise ValueError("a selected forecast cannot also be skipped")
        elif not row.skip_reason:
            raise ValueError("a missing forecast requires an explicit reason")
    if not eligible:
        return FrozenChoice(origin, None, ordered, "no_in_season_candidates")
    if any(row.selected is None for row in ordered):
        return FrozenChoice(origin, None, ordered, "missing_forecast")
    margins = {
        row.crop: assumptions[row.crop].margin(row.selected.p50)
        for row in ordered
        if row.selected is not None
    }
    # Dict insertion is alphabetical; max retains the first key on exact ties.
    return FrozenChoice(origin, max(margins, key=lambda crop: margins[crop]), ordered, None)


class RetrospectiveSimulation:
    """Isolated per-run price basis and predictor cache under the frozen rules.

    Input prices must be nominal. CPI normalization occurs once, before fitting,
    ranking and scoring. Publication timestamps are retained unchanged. The
    cache never crosses datasets or runs, and every fit reconstructs its origin.
    """

    def __init__(
        self,
        records: tuple[PriceObservation, ...],
        cpi: CpiSeries,
        *,
        market: str,
        assumptions: Mapping[Crop, ProductionAssumptions] = ASSUMPTIONS,
    ):
        if not records or any(row.market != market for row in records):
            raise ValueError("one explicit nonempty market series is required")
        if not assumptions or not set(assumptions) <= set(Crop):
            raise ValueError("nonempty canonical crop assumptions are required")
        keys = [(row.crop, row.observation_month) for row in records]
        if len(set(keys)) != len(keys):
            raise ValueError("duplicate crop/observation month")
        self.market = market
        self.assumptions = MappingProxyType(dict(assumptions))
        self._records = tuple(
            replace(
                row,
                price_rand_per_kg=cpi.to_2025(
                    row.price_rand_per_kg, nominal_month=row.observation_month
                ),
            )
            for row in sorted(records, key=lambda row: (row.crop, row.observation_month))
        )
        self._by_crop = {
            crop: tuple(row for row in self._records if row.crop == crop) for crop in Crop
        }
        self._cache: dict[tuple[Crop, str, date, date], Forecast | str] = {}

    def _predictor(self, crop: Crop, method: str) -> Predictor:
        implementations: dict[str, Callable[..., Forecast]] = {
            "historical_range": historical_range,
            "lightgbm": lightgbm_quantiles,
            "same_month_last_year": same_month_last_year,
        }
        implementation = implementations[method]

        def predict(history: tuple[PriceObservation, ...], origin: date, target: date) -> Forecast:
            key = (crop, method, origin, target)
            cached = self._cache.get(key)
            if isinstance(cached, str):
                raise InsufficientHistory(cached)
            if cached is not None:
                return cached
            try:
                result = implementation(
                    history,
                    crop=crop,
                    market=self.market,
                    origin=origin,
                    target=target,
                    policy=POLICY,
                )
            except InsufficientHistory as exc:
                self._cache[key] = str(exc)
                raise
            self._cache[key] = result
            return result

        return predict

    def forecast(self, crop: Crop, origin: date) -> ForecastAudit:
        target = shift_month(origin, self.assumptions[crop].harvest_months)
        records = self._by_crop[crop]
        diagnostic, diagnostic_failure = None, None
        try:
            diagnostic = self._predictor(crop, "same_month_last_year")(records, origin, target)
        except InsufficientHistory as exc:
            diagnostic_failure = str(exc)
        methods = {name: self._predictor(crop, name) for name in ("historical_range", "lightgbm")}
        selection, selected, reason = None, None, None
        failed_folds: tuple[ValidationFold, ...] = ()
        failed_scores: tuple[tuple[str, Decimal | None], ...] = ()
        try:
            with localcontext(Context(prec=28, rounding=ROUND_HALF_EVEN)):
                selection = select_method(
                    records,
                    crop=crop,
                    market=self.market,
                    cutoff=origin,
                    horizon_months=self.assumptions[crop].harvest_months,
                    methods=methods,
                    tie_order=("historical_range", "lightgbm"),
                    policy=POLICY,
                )
            selected = methods[selection.winner](records, origin, target)
        except InsufficientHistory as exc:
            reason = str(exc)
            if isinstance(exc, SelectionUnavailable):
                failed_folds, failed_scores = exc.folds, exc.scores
        return ForecastAudit(
            crop,
            origin,
            target,
            selected,
            selection,
            diagnostic,
            reason,
            diagnostic_failure,
            failed_folds,
            failed_scores,
        )

    def freeze(self, origins: Sequence[date] = HISTORICAL_MONTHS) -> tuple[FrozenChoice, ...]:
        if (
            not origins
            or len(set(origins)) != len(origins)
            or not set(origins) <= set(HISTORICAL_MONTHS)
        ):
            raise ValueError("origins must be unique months within the registered 2012-2024 grid")
        return tuple(
            choose(
                tuple(
                    self.forecast(crop, origin)
                    for crop, inputs in self.assumptions.items()
                    if origin.month in inputs.planting_months
                ),
                origin=origin,
                assumptions=self.assumptions,
            )
            for origin in sorted(origins)
        )

    def score(self, choices: tuple[FrozenChoice, ...]) -> tuple[Decision, ...]:
        """Read harvest outcomes only after the choices have been frozen.

        Version 1 never splices post-2024 prices in, even when supplied. Missing
        prices leave the original recommendation intact and produce a skip.
        """
        if len({choice.origin for choice in choices}) != len(choices):
            raise ValueError("duplicate frozen planting origins")
        for choice in choices:
            if choice != choose(
                choice.forecasts, origin=choice.origin, assumptions=self.assumptions
            ):
                raise ValueError("frozen choice does not match its forecast evidence")
        actual = {
            (row.crop, row.observation_month): row.price_rand_per_kg
            for row in self._records
            if row.observation_month <= LAST_REALIZED_MONTH
        }
        rows = []
        for choice in choices:
            for default in self.assumptions:
                selected = choice.recommended or default
                reason = (
                    "out_of_season"
                    if choice.origin.month not in self.assumptions[default].planting_months
                    else choice.skip_reason
                )
                margins = {}
                if reason is None:
                    for crop in {default, selected}:
                        inputs = self.assumptions[crop]
                        key = (crop, shift_month(choice.origin, inputs.harvest_months))
                        if key not in actual:
                            reason = "missing_realized_price"
                            break
                        margins[crop] = inputs.margin(actual[key])
                rows.append(
                    Decision(choice.origin, default, selected, None, None, reason)
                    if reason is not None
                    else Decision(
                        choice.origin, default, selected, margins[default], margins[selected]
                    )
                )
        return tuple(rows)

    def run(self, origins: Sequence[date] = HISTORICAL_MONTHS) -> Simulation:
        choices = self.freeze(origins)
        return Simulation(choices, self.score(choices))
