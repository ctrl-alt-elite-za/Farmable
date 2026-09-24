"""Actual Parquet writer/reader and command-line validation on synthetic data."""

import json
import subprocess
import sys
from decimal import Decimal as D
from pathlib import Path

import pytest
from farmable_ml.data import Crop
from farmable_ml.snapshot import consumer_json, read_snapshot, validate_bundle, write_snapshot


def bundle():
    return {
        "schema_version": 1,
        "run_id": "synthetic-test",
        "data_kind": "synthetic",
        "as_of": "2025-12-31T00:00:00+00:00",
        "currency": "ZAR",
        "price_basis_year": 2025,
        "sources": [{"name": "invented", "sha256": "a" * 64}],
        "assumptions": ["Synthetic fixture, not a validated forecast."],
        "rows": [
            dict(
                crop=crop.value,
                plant_month=month,
                growing_months=3,
                p10=D(1),
                p50=D(2),
                p90=D(3),
                method="fixture",
                cost_per_ha=D(100),
                yield_kg_per_ha=D(1000),
            )
            for crop in Crop
            for month in range(1, 13)
        ],
    }


def test_snapshot_parquet_roundtrip_and_cli(tmp_path):
    path = tmp_path / "forecasts.parquet"
    write_snapshot(bundle(), path)
    assert read_snapshot(path) == bundle()
    result = subprocess.run(  # noqa: S603 - fixed validator and fixture file
        [sys.executable, str(Path(__file__).with_name("validate_output.py")), str(path)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "synthetic" in result.stdout
    consumer = json.loads(consumer_json(bundle()))
    assert consumer["rows"][0]["p50"] == "2.0000"


def test_parquet_bytes_are_stable_after_row_reordering(tmp_path):
    value = bundle()
    first, second = tmp_path / "one.parquet", tmp_path / "two.parquet"
    write_snapshot(value, first)
    value["rows"].reverse()
    write_snapshot(value, second)
    assert first.read_bytes() == second.read_bytes()


@pytest.mark.parametrize(
    "field,value",
    [
        ("p10", D(0)),
        ("p50", D(-1)),
        ("p90", D("NaN")),
        ("p90", D("0.5")),
        ("plant_month", True),
        ("plant_month", 13),
        ("method", "lightgbm"),
        ("cost_per_ha", D("1.00001")),
    ],
)
def test_snapshot_rejects_invalid_rows(field, value):
    data = bundle()
    data["rows"][0][field] = value
    with pytest.raises(ValueError):
        validate_bundle(data)


def test_snapshot_rejects_missing_duplicate_and_wrong_basis():
    data = bundle()
    data["rows"].pop()
    with pytest.raises(ValueError, match="96"):
        validate_bundle(data)
    data["rows"].append(data["rows"][0])
    with pytest.raises(ValueError, match="duplicate"):
        validate_bundle(data)
    data = bundle()
    data["price_basis_year"] = 2012
    with pytest.raises(ValueError, match="2025"):
        validate_bundle(data)


def test_snapshot_accepts_registered_retrospective_kind():
    data = bundle()
    data["data_kind"] = "retrospective"
    for row in data["rows"]:
        row["method"] = "historical_range"
    validate_bundle(data)
