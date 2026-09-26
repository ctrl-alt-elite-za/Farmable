"""Amendment 2 decision universe and separate tomato price-only forecasts."""

from collections.abc import Mapping
from datetime import date
from decimal import Decimal
from types import MappingProxyType
from typing import Any

from farmable_ml.data import Crop, ObservationPolicy, PriceObservation
from farmable_ml.forecast import historical_range
from farmable_ml.reports import SEVEN_DEFAULT_SCENARIO
from farmable_ml.retrospective import ASSUMPTIONS, ProductionAssumptions

SCENARIO_ID = SEVEN_DEFAULT_SCENARIO
VERSION_ONE_RUN_ID = "c67c0ad8d791c19ad711a8aeaf90a8dad26e60b5bec127c75fe422f63f78429f"
COMPARISON_INTERPRETATION = (
    "The decision universes differ. A change in pooled gains cannot be attributed "
    "to improved model skill."
)
DECISION_ASSUMPTIONS: Mapping[Crop, ProductionAssumptions] = MappingProxyType(
    {crop: value for crop, value in ASSUMPTIONS.items() if crop != Crop.TOMATOES}
)


def render_version_comparison(
    old_sentence: str, old_table: str, new_sentence: str, new_table: str
) -> str:
    """Render the published results together without changing either result."""
    return (
        "# Issue 20 retrospective result comparison\n\n"
        "Version 1 includes eight starting crops and uses a processing-tomato "
        "budget against fresh-market prices. Amendment 2 has seven starting "
        "crops and excludes tomatoes from all decision economics. A difference "
        "in pooled gains cannot be attributed to improved model skill.\n\n"
        "## Version 1: eight defaults\n\n"
        f"{old_sentence.strip()}\n\n{old_table}\n"
        "## Amendment 2: seven defaults\n\n"
        f"{new_sentence.strip()}\n\n{new_table}"
    )


def tomato_price_forecasts(
    records: tuple[PriceObservation, ...], *, market: str
) -> list[dict[str, Any]]:
    """Twelve 2025 target-calendar-month prices; no production or profit fields."""
    cutoff = date(2025, 1, 1)
    rows = []
    for month in range(1, 13):
        target = date(2025, month, 1)
        forecast = historical_range(
            records,
            crop=Crop.TOMATOES,
            market=market,
            origin=cutoff,
            target=target,
            policy=ObservationPolicy.RETROSPECTIVE,
        )
        rows.append(
            {
                "crop": Crop.TOMATOES.value,
                "market": market,
                "target_month": target,
                "as_of": cutoff,
                "method": forecast.method,
                "p10": forecast.p10.quantize(Decimal("0.0001")),
                "p50": forecast.p50.quantize(Decimal("0.0001")),
                "p90": forecast.p90.quantize(Decimal("0.0001")),
                "currency": "ZAR",
                "price_basis_year": 2025,
                "unit": "ZAR/kg",
            }
        )
    return rows


def validate_tomato_price_rows(rows: list[dict[str, Any]]) -> None:
    expected_fields = {
        "crop",
        "market",
        "target_month",
        "as_of",
        "method",
        "p10",
        "p50",
        "p90",
        "currency",
        "price_basis_year",
        "unit",
    }
    if len(rows) != 12 or {row["target_month"] for row in rows} != {
        date(2025, month, 1) for month in range(1, 13)
    }:
        raise ValueError("tomato price artifact requires twelve unique 2025 target months")
    for row in rows:
        if set(row) != expected_fields:
            raise ValueError("tomato price artifact has incorrect columns")
        if (
            row["crop"] != Crop.TOMATOES.value
            or row["as_of"] != date(2025, 1, 1)
            or row["currency"] != "ZAR"
            or row["price_basis_year"] != 2025
            or row["unit"] != "ZAR/kg"
            or row["method"] != "historical_range"
            or row["market"] != "joburg"
        ):
            raise ValueError("tomato price artifact has inconsistent metadata")
        if not all(isinstance(row[name], Decimal) for name in ("p10", "p50", "p90")):
            raise ValueError("tomato price quantiles must be decimals")
        if not (Decimal(0) < row["p10"] <= row["p50"] <= row["p90"]):
            raise ValueError("tomato price quantiles must be positive and ordered")
