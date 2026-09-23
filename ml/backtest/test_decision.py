"""Synthetic decisions prove information separation, not historical data coverage."""

from dataclasses import replace
from datetime import date
from decimal import Decimal as D

import pytest
from farmable_ml.data import Crop, PriceObservation
from farmable_ml.decision import Candidate, recommend, score_recommendation
from farmable_ml.forecast import historical_range


def candidates(future_price):
    origin = date(2012, 1, 1)
    rows = tuple(
        PriceObservation(
            crop,
            "synthetic",
            date(year, 6, 1),
            date(year, 7, 15),
            D(future_price) if year >= 2012 else D(price),
            "a" * 64,
        )
        for crop, price in [(Crop.CABBAGE, "10"), (Crop.CARROTS, "20")]
        for year in range(2008, 2014)
    )
    return tuple(
        Candidate(
            historical_range(
                rows, crop=crop, market="synthetic", origin=origin, target=date(2012, 6, 1)
            ),
            D(100),
            D(200),
            D(2),
            date(2011, 1, 1),
            "synthetic_constant_ZAR",
        )
        for crop in (Crop.CABBAGE, Crop.CARROTS)
    )


def test_no_lookahead_recommendation():
    eligible = frozenset((Crop.CABBAGE, Crop.CARROTS))
    choice = recommend(candidates("1"), eligible=eligible)
    assert choice == recommend(candidates("99999"), eligible=eligible)
    assert choice.selected == Crop.CARROTS
    keys = [(crop, date(2012, 6, 1)) for crop in eligible]
    good = score_recommendation(
        choice,
        default=Crop.CABBAGE,
        actual_prices={keys[0]: D(10), keys[1]: D(20)},
        reporting_multipliers=dict.fromkeys(keys, D(1)),
    )
    missing = score_recommendation(
        choice, default=Crop.CABBAGE, actual_prices={}, reporting_multipliers={}
    )
    assert good.gain is not None
    assert missing.skip_reason is not None
    assert good.recommended == missing.recommended == Crop.CARROTS


def test_missing_candidates_and_unavailable_costs_are_rejected():
    values = candidates("1")
    with pytest.raises(ValueError, match="exactly one"):
        recommend(values[:1], eligible=frozenset((Crop.CABBAGE, Crop.CARROTS)))
    with pytest.raises(ValueError, match="before planting"):
        replace(values[0], available_on=date(2025, 1, 1))


def test_negative_margins_and_ties_use_fixed_alphabetical_rule():
    values = tuple(
        replace(
            value,
            cost_rand_per_ha=D(10000),
            forecast=replace(value.forecast, p10=D(1), p50=D(1), p90=D(1)),
        )
        for value in reversed(candidates("1"))
    )
    choice = recommend(values, eligible=frozenset((Crop.CABBAGE, Crop.CARROTS)))
    assert choice.selected == Crop.CABBAGE
    assert all(value.predicted_margin() < 0 for value in values)


def test_future_cpi_deflation_of_modern_costs_can_reverse_the_winner():
    # R04 counterexample: future CPI changes costs, not a common net-margin scale.
    def margins(future_cpi):
        return (D(100) - D(120) * 100 / future_cpi, D(70) - D(40) * 100 / future_cpi)

    assert margins(D(200)) == (D(40), D(50))
    assert margins(D(400)) == (D(70), D(60))


@pytest.mark.parametrize("multiplier", [D("0.5"), D(2), D(100)])
def test_reporting_cpi_changes_scores_without_changing_frozen_recommendation(multiplier):
    values = candidates("1")
    eligible = frozenset(value.forecast.crop for value in values)
    choice = recommend(values, eligible=eligible)
    keys = [(value.forecast.crop, value.forecast.target) for value in values]
    scored = score_recommendation(
        choice,
        default=Crop.CABBAGE,
        actual_prices=dict.fromkeys(keys, D(15)),
        reporting_multipliers=dict.fromkeys(keys, multiplier),
    )
    assert scored.recommended == choice.selected == Crop.CARROTS
    assert scored.default_margin == D(650) * multiplier
    assert recommend(values, eligible=eligible) == choice


@pytest.mark.parametrize("available_on", [date(2012, 1, 1), date(2025, 1, 1)])
@pytest.mark.parametrize("cost", [D(1), D(999999)])
def test_future_cost_vintage_is_rejected_regardless_of_its_value(available_on, cost):
    with pytest.raises(ValueError, match="before planting"):
        replace(candidates("1")[0], available_on=available_on, cost_rand_per_ha=cost)
