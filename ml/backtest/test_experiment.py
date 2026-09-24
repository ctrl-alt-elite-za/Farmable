"""Integrated orchestration tests use synthetic prices only, never source outcomes."""

from dataclasses import replace
from datetime import date
from decimal import Decimal as D

import pytest
from farmable_ml import retrospective
from farmable_ml.data import Crop, ObservationPolicy, PriceObservation, observations_before
from farmable_ml.experiment import METHODS, Experiment
from farmable_ml.forecast import Forecast, InsufficientHistory, shift_month
from farmable_ml.scenario import MARKET


def synthetic_records():
    return tuple(
        PriceObservation(
            crop,
            MARKET,
            shift_month(date(2000, 1, 1), index),
            shift_month(date(2000, 1, 1), index + 1),
            D(10 + index % 12 + list(Crop).index(crop)),
            "a" * 64,
            availability_kind="analytical_next_month",
        )
        for crop in Crop
        for index in range(300)
    )


@pytest.fixture
def simple_models(monkeypatch):
    def model(records, *, crop, market, origin, target, policy):
        assert policy is ObservationPolicy.RETROSPECTIVE
        history = [
            r
            for r in observations_before(records, origin, policy=policy)
            if r.crop == crop and r.market == market
        ]
        assert all(row.observation_month < origin for row in history)
        if not history:
            raise InsufficientHistory("empty synthetic history")
        price = sum((r.price_rand_per_kg for r in history), D(0)) / len(history)
        return Forecast(crop, origin, target, "historical_range", price, price, price)

    for name in METHODS:
        monkeypatch.setitem(METHODS, name, model)
    monkeypatch.setattr(retrospective, "historical_range", model)
    monkeypatch.setattr(retrospective, "lightgbm_quantiles", model)
    monkeypatch.setattr(retrospective, "same_month_last_year", model)


def test_analytical_cutoff_includes_previous_month_but_publication_cutoff_does_not():
    row = synthetic_records()[0]
    assert observations_before((row,), row.available_on) == ()
    assert observations_before(
        (row,), row.available_on, policy=ObservationPolicy.RETROSPECTIVE
    ) == (row,)
    strict = replace(row, availability_kind="publication")
    assert observations_before((strict,), row.available_on) == ()
    with pytest.raises(ValueError, match="first day of the next month"):
        replace(row, available_on=date(2000, 3, 1))


def test_no_lookahead_recommendation_integrated(simple_models):
    records = synthetic_records()
    origin = date(2018, 2, 1)
    changed = tuple(
        replace(row, price_rand_per_kg=D("999999")) if row.observation_month >= origin else row
        for row in records
    )
    first, second = Experiment(records), Experiment(changed)
    assert first.recommendation(origin) == second.recommendation(origin)
    assert first.selections == second.selections
    assert first.forecast_ledger() == second.forecast_ledger()
    # Future outcomes may change scores but must not change the frozen choices.
    assert [r.recommended for r in first.decisions((origin,))] == [
        r.recommended for r in second.decisions((origin,))
    ]


def test_decision_grid_retains_seasonality_and_missing_outcome_skips(simple_models):
    rows = Experiment(synthetic_records()).decisions((date(2024, 12, 1),))
    assert len(rows) == 8
    assert {row.skip_reason for row in rows} == {"out_of_season", "missing_realized_price"}
    assert all(row.gain is None for row in rows)


def test_missing_candidate_does_not_silently_change_recommendation(simple_models, monkeypatch):
    experiment = Experiment(synthetic_records())
    original = experiment.selected_forecast

    def missing(crop, origin):
        if crop == Crop.CABBAGE:
            raise InsufficientHistory("missing cabbage")
        return original(crop, origin)

    monkeypatch.setattr(experiment, "selected_forecast", missing)
    rows = experiment.decisions((date(2020, 2, 1),))
    assert all(row.skip_reason in {"unavailable_forecast", "out_of_season"} for row in rows)


def test_experiment_rejects_implicit_basis_and_duplicates():
    records = synthetic_records()
    with pytest.raises(ValueError, match="explicit Joburg"):
        Experiment((replace(records[0], availability_kind="publication"),))
    with pytest.raises(ValueError, match="duplicate"):
        Experiment((records[0], records[0]))
