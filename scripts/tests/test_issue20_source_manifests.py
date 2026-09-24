"""Fail closed when committed Issue 20 source identities are incomplete."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_calendar_manifest_rejects_the_truncated_winter_download():
    manifest = json.loads((ROOT / "ml/data/calendar_source_audit.json").read_text())
    assert manifest["status"] == "source_values_reviewed_not_approved_for_historical_features"
    assert {source["kind"] for source in manifest["sources"]} == {"summer", "winter"}
    for source in manifest["sources"]:
        assert source["structurally_readable"] is True
        assert source["pages"] > 0
        assert len(source["sha256"]) == 64
        assert source["pdf_metadata"]["release_evidence"] is False

    winter = next(source for source in manifest["sources"] if source["kind"] == "winter")
    superseded = winter["superseded_download"]
    assert superseded["structurally_readable"] is False
    assert superseded["pages"] == 0
    assert superseded["sha256"] != winter["sha256"]


def test_post_2024_market_manifest_records_partial_coverage_without_overclaiming():
    manifest = json.loads((ROOT / "ml/data/post_2024_market_source_audit.json").read_text())
    source = manifest["source"]
    coverage = manifest["coverage"]

    assert manifest["status"] == "partial_coverage_not_approved_for_complete_historical_run"
    assert source["structurally_readable"] is True
    assert source["pages"] == 39
    assert len(source["sha256"]) == 64
    assert source["pdf_metadata"]["release_evidence"] is False
    assert coverage["months"] == [
        "2024-10",
        "2024-11",
        "2024-12",
        "2025-01",
        "2025-02",
        "2025-03",
    ]
    assert set(coverage["crops"]) == {
        "butternut",
        "cabbage",
        "carrots",
        "green_beans",
        "onions",
        "potatoes",
        "tomatoes",
    }
    assert coverage["missing_required_crops"] == ["spinach"]
    assert manifest["availability"]["available_on"] is None
    assert manifest["availability"]["status"] == "unknown_blocks_historical_use"
