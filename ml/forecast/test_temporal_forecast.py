"""Hand-checkable temporal fixtures; no real crop-switch outcomes are evaluated."""

from dataclasses import replace
from datetime import date
from decimal import Decimal as D

import pytest
from farmable_ml.data import Crop, PriceObservation
from farmable_ml.forecast import (
    Forecast,
    InsufficientHistory,
    historical_range,
    same_month_last_year,
    select_method,
    shift_month,
)


def record(month, price="10", available=None):
    return PriceObservation(
        Crop.CABBAGE,
        "synthetic",
        month,
        available or shift_month(month, 1).replace(day=15),
        D(price),
        "a" * 64,
    )


def test_no_lookahead_forecast():
    records = tuple(
        record(date(year, 6, 1), str(year - 2000)) for year in range(2000, 2005) if year > 2000
    )
    cutoff = date(2004, 1, 1)
    changed = tuple(
        replace(r, price_rand_per_kg=D("999999")) if r.available_on >= cutoff else r
        for r in records
    )
    args = dict(crop=Crop.CABBAGE, market="synthetic", origin=cutoff, target=date(2004, 6, 1))
    first = historical_range(records, **args)
    assert first.values == (D("1.2"), D("2"), D("2.8"))
    assert first == historical_range(changed, **args)
    assert same_month_last_year(records, **args) == same_month_last_year(changed, **args)


def test_last_year_target_must_already_be_available():
    with pytest.raises(InsufficientHistory):
        same_month_last_year(
            (record(date(2011, 12, 1)),),
            crop=Crop.CABBAGE,
            market="synthetic",
            origin=date(2012, 1, 1),
            target=date(2012, 12, 1),
        )
    assert shift_month(date(2012, 11, 1), 3) == date(2013, 2, 1)


def test_method_selection_picks_backtest_winner():
    records = tuple(record(shift_month(date(2000, 1, 1), offset)) for offset in range(60))
    seen = []

    def predict(value):
        def run(history, origin, target):
            assert all(row.available_on < origin for row in history)
            seen.append(origin)
            return Forecast(Crop.CABBAGE, origin, target, "test", D(value), D(value), D(value))

        return run

    args = dict(
        crop=Crop.CABBAGE,
        market="synthetic",
        cutoff=date(2004, 1, 1),
        horizon_months=3,
        methods={"bad": predict("5"), "good": predict("10")},
        tie_order=("bad", "good"),
        validation_months=12,
        minimum_folds=10,
    )
    selection = select_method(records, **args)
    assert selection.winner == "good"
    assert dict(selection.scores)["good"] == 0
    assert len(set(seen)) == 11  # December is not published by the January cutoff.
    changed = tuple(
        replace(r, price_rand_per_kg=D("5")) if r.available_on >= args["cutoff"] else r
        for r in records
    )
    assert select_method(changed, **args) == selection
    args["cutoff"] = date(2005, 1, 1)
    assert select_method(changed, **args).winner == "bad"


def test_failed_method_is_not_rewarded_for_skipping_targets():
    records = tuple(record(shift_month(date(2000, 1, 1), offset)) for offset in range(36))

    def reliable(history, origin, target):
        return Forecast(Crop.CABBAGE, origin, target, "reliable", D(9), D(9), D(9))

    def selective(history, origin, target):
        if target.month == 3:
            raise InsufficientHistory("missing features")
        return Forecast(Crop.CABBAGE, origin, target, "selective", D(10), D(10), D(10))

    selected = select_method(
        records,
        crop=Crop.CABBAGE,
        market="synthetic",
        cutoff=date(2003, 1, 1),
        horizon_months=2,
        methods={"selective": selective, "reliable": reliable},
        tie_order=("selective", "reliable"),
        minimum_folds=10,
        validation_months=12,
    )
    assert selected.winner == "reliable"
    assert dict(selected.scores)["selective"] is None
