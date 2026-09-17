"""Invented, versioned arithmetic fixtures, NOT researched crop or market recommendations."""

from datetime import date
from decimal import Decimal

from .schemas import SampleCost, SampleCrop, SampleScenario

DEMO_SCENARIO = SampleScenario(
    scenario_id="hammanskraal-september-2026",
    data_version="sample-v1",
    label="Prototype using sample crop and market data. Not a live forecast.",
    planting_start=date(2026, 9, 1),
    planting_end=date(2026, 9, 30),
    crops=(
        SampleCrop(
            crop="cabbage",
            yield_kg_per_m2=Decimal("2"),
            price_cents_per_kg=500,
            costs=(
                SampleCost(category="seed", cents_per_m2=120),
                SampleCost(category="fertiliser", cents_per_m2=180),
                SampleCost(category="water", cents_per_m2=90),
                SampleCost(category="labour", cents_per_m2=210),
                SampleCost(category="transport_packaging", cents_per_m2=150),
            ),
            harvest_days_min=90,
            harvest_days_max=110,
        ),
        SampleCrop(
            crop="spinach",
            yield_kg_per_m2=Decimal("1.5"),
            price_cents_per_kg=800,
            costs=(
                SampleCost(category="seed", cents_per_m2=80),
                SampleCost(category="fertiliser", cents_per_m2=120),
                SampleCost(category="water", cents_per_m2=80),
                SampleCost(category="labour", cents_per_m2=170),
                SampleCost(category="transport_packaging", cents_per_m2=150),
            ),
            harvest_days_min=35,
            harvest_days_max=50,
        ),
    ),
    assumptions=(
        "All yields, prices, costs and growth durations are invented demonstration inputs.",
        "Quantity = allocated square metres multiplied by sample kilograms per square metre.",
        "Sales = quantity multiplied by sample price; margin subtracts only the listed costs.",
        "Budget means total listed spending fits starting cash; this is not a cash-flow forecast.",
        "Market/agent commissions, losses, taxes and unlisted overheads are not included.",
        "No soil suitability, irrigation availability or weather risk has been assessed.",
        "Allocation uses equal blocks; unplanted blocks are allowed and earn no sales.",
        "Harvest dates are illustrative windows, not promised yields or payment dates.",
    ),
)
