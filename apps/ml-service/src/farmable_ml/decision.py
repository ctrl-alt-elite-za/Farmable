"""Separate planting-time recommendations from retrospective outcome scoring."""

from collections.abc import Mapping
from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from farmable_ml.data import Crop
from farmable_ml.forecast import Forecast
from farmable_ml.money import gross_margin


@dataclass(frozen=True)
class Candidate:
    forecast: Forecast
    yield_kg_per_ha: Decimal
    cost_rand_per_ha: Decimal
    occupied_months: Decimal
    available_on: date
    price_basis: str
    assumption_kind: str = "historical_vintage"
    marketing_rate: Decimal = Decimal(0)

    def __post_init__(self) -> None:
        if self.assumption_kind not in {"historical_vintage", "fixed_scenario"}:
            raise ValueError("unknown candidate assumption kind")
        if (
            self.assumption_kind == "historical_vintage"
            and self.available_on >= self.forecast.origin
        ):
            raise ValueError("candidate cost/yield must be available before planting")
        if not self.price_basis.strip():
            raise ValueError("candidate requires an explicit common price/cost basis")
        if not self.marketing_rate.is_finite() or not 0 <= self.marketing_rate < 1:
            raise ValueError("marketing_rate must be a Decimal in [0, 1)")
        self.predicted_margin()

    def predicted_margin(self) -> Decimal:
        return gross_margin(
            price_rand_per_kg=self.forecast.p50 * (1 - self.marketing_rate),
            yield_kg_per_ha=self.yield_kg_per_ha,
            cost_rand_per_ha=self.cost_rand_per_ha,
            occupied_months=self.occupied_months,
        )


@dataclass(frozen=True)
class Recommendation:
    origin: date
    selected: Crop
    candidates: tuple[Candidate, ...]


def recommend(candidates: tuple[Candidate, ...], *, eligible: frozenset[Crop]) -> Recommendation:
    """Maximum predicted margin, alphabetical exact ties, including all-negative sets.

    Calendar eligibility must be established before calling. Missing candidate
    forecasts invalidate the origin; outcome availability is never an input.
    """
    if not candidates or not eligible:
        raise ValueError("no eligible candidates")
    crops = [candidate.forecast.crop for candidate in candidates]
    if len(set(crops)) != len(crops) or set(crops) != eligible:
        raise ValueError("exactly one forecast per eligible crop is required")
    if len({candidate.forecast.origin for candidate in candidates}) != 1:
        raise ValueError("candidates must share the same origin")
    if len({candidate.price_basis for candidate in candidates}) != 1:
        raise ValueError("candidate prices and costs must share the same basis")
    ordered = tuple(sorted(candidates, key=lambda candidate: candidate.forecast.crop))
    winner = max(ordered, key=lambda candidate: candidate.predicted_margin())
    return Recommendation(winner.forecast.origin, winner.forecast.crop, ordered)


@dataclass(frozen=True)
class Decision:
    origin: date
    default: Crop
    recommended: Crop
    default_margin: Decimal | None
    recommended_margin: Decimal | None
    skip_reason: str | None = None

    def __post_init__(self) -> None:
        if (
            self.origin.day != 1
            or not isinstance(self.default, Crop)
            or not isinstance(self.recommended, Crop)
        ):
            raise ValueError("decision requires a planting month and canonical crops")
        amounts = (self.default_margin, self.recommended_margin)
        if self.skip_reason is None:
            if any(value is None or not value.is_finite() for value in amounts):
                raise ValueError("scorable decisions require finite margins")
            if self.default == self.recommended and self.default_margin != self.recommended_margin:
                raise ValueError("no-switch margins must be identical")
        elif not self.skip_reason.strip() or any(value is not None for value in amounts):
            raise ValueError("skipped decisions require a reason and no partial margins")

    @property
    def gain(self) -> Decimal | None:
        if self.default_margin is None or self.recommended_margin is None:
            return None
        return self.recommended_margin - self.default_margin


def score_recommendation(
    recommendation: Recommendation,
    *,
    default: Crop,
    actual_prices: Mapping[tuple[Crop, date], Decimal],
    reporting_multipliers: Mapping[tuple[Crop, date], Decimal],
) -> Decision:
    """Score a frozen choice; missing outcomes never cause a replacement choice.

    Prices MUST already use each candidate's prediction-time price basis. The
    caller supplies a separately audited positive conversion of each resulting
    margin into the common reporting basis (2025 ZAR for the real experiment).
    This function does not invent CPI values or convert 2025 budgets backwards.
    """
    lookup = {candidate.forecast.crop: candidate for candidate in recommendation.candidates}
    if default not in lookup:
        raise ValueError("default must be an eligible candidate")
    margins = {}
    for crop in {default, recommendation.selected}:
        candidate = lookup[crop]
        key = (crop, candidate.forecast.target)
        if key not in actual_prices or key not in reporting_multipliers:
            return Decision(
                recommendation.origin,
                default,
                recommendation.selected,
                None,
                None,
                "missing_harvest_price_or_reporting_conversion",
            )
        multiplier = reporting_multipliers[key]
        if not multiplier.is_finite() or multiplier <= 0:
            raise ValueError("reporting multipliers must be finite and positive")
        margins[crop] = (
            gross_margin(
                price_rand_per_kg=actual_prices[key] * (1 - candidate.marketing_rate),
                yield_kg_per_ha=candidate.yield_kg_per_ha,
                cost_rand_per_ha=candidate.cost_rand_per_ha,
                occupied_months=candidate.occupied_months,
            )
            * multiplier
        )
    return Decision(
        recommendation.origin,
        default,
        recommendation.selected,
        margins[default],
        margins[recommendation.selected],
    )
