"""Amendment 2 leaves the archived economics intact and isolates tomato prices."""

import json
from dataclasses import replace
from datetime import date
from decimal import Decimal

import pyarrow.parquet as pq
import pytest
import run_seven_default as runner
from check_protocol_first import ProtocolGateError
from farmable_ml.data import Crop
from farmable_ml.forecast import shift_month
from farmable_ml.reports import Bootstrap, build_report
from farmable_ml.scenario import MARKET
from farmable_ml.seven_default import (
    DECISION_ASSUMPTIONS,
    tomato_price_forecasts,
    validate_tomato_price_rows,
)
from test_experiment import simple_models, synthetic_records  # noqa: F401


def test_gate_precedes_real_data_access(tmp_path, monkeypatch):
    def reject(**kwargs):
        raise ProtocolGateError("amendment not merged")

    monkeypatch.setattr(runner, "check_amendment_two_merged", reject)
    with pytest.raises(ProtocolGateError, match="amendment not merged"):
        runner.run(tmp_path, tmp_path / "missing", tmp_path / "output")
    assert not (tmp_path / "output").exists()


def test_tomato_price_only_forecasts_ignore_post_cutoff_prices():
    records = synthetic_records()
    later = tuple(
        replace(
            row,
            observation_month=shift_month(row.observation_month, 12),
            available_on=shift_month(row.available_on, 12),
            price_rand_per_kg=Decimal("9999"),
        )
        for row in records
        if row.crop == Crop.TOMATOES and row.observation_month.year == 2024
    )
    rows = tomato_price_forecasts(records, market=MARKET)
    assert rows == tomato_price_forecasts(records + later, market=MARKET)
    validate_tomato_price_rows(rows)
    assert {row["target_month"] for row in rows} == {date(2025, month, 1) for month in range(1, 13)}
    assert all("yield" not in field and "cost" not in field for field in rows[0])
    with pytest.raises(ValueError, match="incorrect columns"):
        validate_tomato_price_rows([dict(row, profit=0) for row in rows])


def test_amended_runner_is_reproducible_and_excludes_tomato_economics(
    tmp_path,
    monkeypatch,
    simple_models,  # noqa: F811
):
    records = tuple(row for row in synthetic_records() if row.observation_month.year >= 2008)
    monkeypatch.setattr(runner, "check_amendment_two_merged", lambda **kwargs: "fixture")
    monkeypatch.setattr(runner, "identity", lambda *args: {"synthetic_test": True})
    monkeypatch.setattr(runner, "load_workbooks", lambda *args: records)
    monkeypatch.setattr(
        runner,
        "build_report",
        lambda rows, **kwargs: build_report(rows, **kwargs, config=Bootstrap(replicates=100)),
    )
    first, second = tmp_path / "first", tmp_path / "second"
    run_id = runner.run(runner.ROOT, tmp_path, first)
    monkeypatch.setattr(runner, "load_workbooks", lambda *args: tuple(reversed(records)))
    assert runner.run(runner.ROOT, tmp_path, second) == run_id
    files = sorted(path.relative_to(first) for path in first.rglob("*") if path.is_file())
    for relative in files:
        assert (first / relative).read_bytes() == (second / relative).read_bytes(), relative
    report = json.loads(
        (first / "backtest/results" / run_id / "decision_backtest.json").read_bytes()
    )
    assert report["coverage"]["decision_keys"] == 1092
    assert set(report["results"]) == {crop.value for crop in DECISION_ASSUMPTIONS} | {"pooled"}
    assert Crop.TOMATOES.value in report["excluded"]
    ledger = pq.read_table(first / "backtest/results" / run_id / "decision_ledger.parquet")
    assert ledger.num_rows == 1092
    assert all(
        row["default"] != Crop.TOMATOES.value and row["recommended"] != Crop.TOMATOES.value
        for row in ledger.to_pylist()
    )
    tomato = json.loads(
        (first / "forecast/results" / run_id / "tomato_price_forecasts.json").read_bytes()
    )
    assert len(tomato["rows"]) == 12
    assert {"cost", "yield", "profit", "harvest_offset"}.isdisjoint(tomato["rows"][0])
    sentence = (first / "backtest/results" / run_id / "slide_sentence.txt").read_text()
    assert "Tomatoes excluded" in sentence
