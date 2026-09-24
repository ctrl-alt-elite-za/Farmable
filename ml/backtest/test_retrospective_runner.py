"""Public runner must fail closed before loading any real input or writing output."""

from pathlib import Path

import pytest
import run_retrospective as runner
from check_protocol_first import ProtocolGateError
from farmable_ml.reports import Bootstrap, build_report
from farmable_ml.snapshot import read_snapshot
from test_experiment import simple_models, synthetic_records  # noqa: F401


def test_runner_enforces_protocol_gate_before_any_data_read(tmp_path, monkeypatch):
    def reject(**kwargs):
        raise ProtocolGateError("unmerged protocol")

    monkeypatch.setattr(runner, "check_protocol_first", reject)
    with pytest.raises(ProtocolGateError, match="unmerged protocol"):
        runner.run(tmp_path, tmp_path / "absent-workbooks", tmp_path / "output")
    assert not (tmp_path / "output").exists()


def test_workbook_loader_rejects_hash_mismatch_before_parsing(tmp_path, monkeypatch):
    import json

    sources = [
        {"year": str(year), "filename": f"{year}.xls", "bytes": 4, "sha256": "a" * 64}
        for year in range(2008, 2025)
    ]
    audit = tmp_path / "audit.json"
    audit.write_text(json.dumps({"sources": sources}))
    (tmp_path / "2008.xls").write_bytes(b"fake")

    def must_not_parse(path: Path):
        pytest.fail("unverified workbook was parsed")

    monkeypatch.setattr(runner, "read_sheet", must_not_parse)
    with pytest.raises(ValueError, match="bytes/hash mismatch"):
        runner.load_workbooks(audit, tmp_path)


def test_reproducible_output_integrated(tmp_path, monkeypatch, simple_models):  # noqa: F811
    from types import SimpleNamespace

    import pyarrow.parquet as pq

    records = tuple(row for row in synthetic_records() if row.observation_month.year >= 2008)
    monkeypatch.setattr(
        runner, "check_protocol_first", lambda **kwargs: SimpleNamespace(protocol_commit="fixture")
    )
    monkeypatch.setattr(runner, "identity", lambda *args: {"synthetic_test": True})
    monkeypatch.setattr(runner, "load_workbooks", lambda *args: records)
    monkeypatch.setattr(
        runner,
        "build_report",
        lambda rows, **kwargs: build_report(rows, **kwargs, config=Bootstrap(replicates=100)),
    )
    first, second = tmp_path / "first", tmp_path / "second"
    run_id = runner.run(runner.ROOT, tmp_path, first)
    # Input ordering must not affect model fitting, bootstrap, Parquet or manifest bytes.
    monkeypatch.setattr(runner, "load_workbooks", lambda *args: tuple(reversed(records)))
    assert runner.run(runner.ROOT, tmp_path, second) == run_id
    files = sorted(path.relative_to(first) for path in first.rglob("*") if path.is_file())
    assert len(files) == 10
    for relative in files:
        assert (first / relative).read_bytes() == (second / relative).read_bytes(), relative
    bundle = read_snapshot(first / "forecast/results" / run_id / "forecasts.parquet")
    assert len(bundle["rows"]) == 96
    from farmable_backend.forecast_contract import ForecastBundle
    from farmable_backend.forecasts import quality_checks

    consumer = ForecastBundle.model_validate_json(
        (first / "forecast/results" / run_id / "forecast.json").read_bytes()
    )
    assert quality_checks(consumer, None, "retrospective") == []
    assert "data_mode_mismatch" in quality_checks(consumer, None, "historical")
    ledger = pq.read_table(first / "backtest/results" / run_id / "decision_ledger.parquet")
    assert ledger.num_rows == 1248
    forecasts = pq.read_table(first / "forecast/results" / run_id / "forecast_ledger.parquet")
    assert {"p10", "p50", "p90", "failure"} <= set(forecasts.column_names)
    assert any(row["p50"] is not None for row in forecasts.to_pylist())
    sentence = (first / "backtest/results" / run_id / "slide_sentence.txt").read_text()
    assert "using only data available at planting time" not in sentence


def test_ledger_retains_forecasts_when_first_row_is_a_failure(tmp_path):
    import pyarrow.parquet as pq

    path = tmp_path / "ledger.parquet"
    runner.write_ledger([{"failure": "too early"}, {"p50": "1.25"}], path)
    assert pq.read_table(path).to_pylist() == [
        {"failure": "too early", "p50": None},
        {"failure": None, "p50": "1.25"},
    ]
