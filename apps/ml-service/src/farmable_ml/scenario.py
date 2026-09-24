"""Frozen assumptions for registered Issue 20 retrospective protocol version 1."""

from dataclasses import dataclass
from datetime import date
from decimal import Decimal

from farmable_ml.cpi import CpiSeries
from farmable_ml.data import Crop, PriceObservation
from farmable_ml.forecast import shift_month

D = Decimal
SCENARIO_ID = "retrospective_fixed_2025_v1"
MARKET = "joburg"


@dataclass(frozen=True)
class CropAssumption:
    planting_months: frozenset[int]
    harvest_offset_months: int
    yield_kg_per_ha: Decimal
    cost_rand_per_ha: Decimal
    marketing_rate: Decimal


ASSUMPTIONS = {
    Crop.BUTTERNUT: CropAssumption(
        frozenset({9, 10, 11}), 5, D("22500"), D("60756.87"), D("0.125")
    ),
    Crop.CABBAGE: CropAssumption(
        frozenset({1, 2, 3, 4, 5, 11, 12}), 3, D("75000"), D("115183.85"), D("0.125")
    ),
    Crop.CARROTS: CropAssumption(
        frozenset({1, 2, 3, 8, 9, 10}), 4, D("50000"), D("68312.94"), D("0.125")
    ),
    Crop.GREEN_BEANS: CropAssumption(
        frozenset({1, 9, 10, 11, 12}), 3, D("10000"), D("136357.03"), D("0.125")
    ),
    Crop.ONIONS: CropAssumption(frozenset({2, 3}), 7, D("42500"), D("108783.41"), D("0.125")),
    Crop.POTATOES: CropAssumption(
        frozenset({1, 2, 7, 8, 9, 10}), 5, D("45000"), D("181097.86"), D("0.125")
    ),
    Crop.SPINACH: CropAssumption(
        frozenset({1, 2, 3, 4, 8, 9, 10, 11, 12}), 3, D("20000"), D("167412.66"), D("0.125")
    ),
    Crop.TOMATOES: CropAssumption(frozenset({8, 9, 10, 11}), 3, D("62500"), D("168968.20"), D("0")),
}


def eligible_crops(origin: date) -> frozenset[Crop]:
    if origin.day != 1:
        raise ValueError("origin must be the first day of a month")
    return frozenset(
        crop for crop, value in ASSUMPTIONS.items() if origin.month in value.planting_months
    )


def to_retrospective_2025(
    records: tuple[PriceObservation, ...], cpi: CpiSeries
) -> tuple[PriceObservation, ...]:
    """Normalize current-vintage prices and apply the registered analytical cutoff."""
    return tuple(
        PriceObservation(
            crop=row.crop,
            market=MARKET,
            observation_month=row.observation_month,
            available_on=shift_month(row.observation_month, 1),
            price_rand_per_kg=cpi.to_2025(
                row.price_rand_per_kg, nominal_month=row.observation_month
            ),
            source_sha256=row.source_sha256,
            availability_kind="analytical_next_month",
        )
        for row in records
    )
