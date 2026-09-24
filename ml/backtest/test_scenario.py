"""Registered retrospective assumptions remain explicit and deterministic."""

from datetime import date
from decimal import Decimal as D

from farmable_ml.cpi import CpiSeries
from farmable_ml.data import Crop, PriceObservation
from farmable_ml.retrospective import ASSUMPTIONS as REGISTERED_ASSUMPTIONS
from farmable_ml.scenario import ASSUMPTIONS, eligible_crops, to_retrospective_2025


def test_scenario_covers_every_crop_and_uses_frozen_values():
    assert set(ASSUMPTIONS) == set(Crop)
    assert Crop.ONIONS in eligible_crops(date(2020, 2, 1))
    assert Crop.ONIONS not in eligible_crops(date(2020, 4, 1))
    assert ASSUMPTIONS[Crop.TOMATOES].marketing_rate == 0


def test_runner_assumptions_match_the_registered_simulation_core():
    assert set(ASSUMPTIONS) == set(REGISTERED_ASSUMPTIONS)
    for crop, runner in ASSUMPTIONS.items():
        registered = REGISTERED_ASSUMPTIONS[crop]
        assert runner.planting_months == registered.planting_months
        assert runner.harvest_offset_months == registered.harvest_months
        assert runner.yield_kg_per_ha == registered.yield_kg_per_ha
        assert runner.cost_rand_per_ha == registered.cost_2025_rand_per_ha
        assert runner.marketing_rate == registered.marketing_rate


def test_current_vintage_normalization_uses_next_month_analytical_cutoff():
    cpi = CpiSeries(
        "c" * 64,
        tuple((date(2025, month, 1), D(100)) for month in range(1, 13))
        + ((date(2012, 1, 1), D(50)),),
    )
    source = PriceObservation(
        Crop.CABBAGE,
        "source",
        date(2012, 1, 1),
        date(2021, 1, 1),
        D(10),
        "a" * 64,
    )
    normalized = to_retrospective_2025((source,), cpi)[0]
    assert normalized.market == "joburg"
    assert normalized.available_on == date(2012, 2, 1)
    assert normalized.price_rand_per_kg == 20
