"""Fabricated ledgers test the registered wording, never real experiment results."""

import json
from dataclasses import replace
from datetime import date
from decimal import Decimal as D

import pytest
from farmable_ml.data import Crop
from farmable_ml.decision import Decision
from farmable_ml.reports import (
    Bootstrap,
    build_report,
    render_sentence,
    render_table,
    write_synthetic_report,
)

SCENARIO = "retrospective_fixed_2025"


def ledger():
    crops = list(Crop)
    return tuple(
        Decision(date(year, month, 1), crop, crops[(index + 1) % 8], D(100), D(110))
        for year in range(2012, 2025)
        for month in range(1, 13)
        for index, crop in enumerate(crops)
    )


def report(rows=None, *, data_kind="synthetic", **kwargs):
    return build_report(
        ledger() if rows is None else rows,
        data_kind=data_kind,
        scenario=SCENARIO,
        input_hashes={"fabricated_fixture": "a" * 64},
        config=Bootstrap(replicates=100),
        **kwargs,
    )


def test_registered_sentence_uses_retrospective_wording_and_synthetic_warning():
    document = report()
    assert document["schema_version"] == 3
    assert document["scenario"] == SCENARIO
    assert render_sentence(document) == (
        "SYNTHETIC TEST FIXTURE — NOT A REAL RESULT.\n"
        "In a retrospective fixed-2025-input simulation of 1248 scorable planting decisions "
        "(2012-01–2024-12), when Farmable recommended switching away from a farmer's usual "
        "crop, the switch earned more profit 100.0% of the time, with a median increase of "
        "R 10.0 per hectare per month (ranging from 100.0% to 100.0% across the 8 starting "
        "crops). Uses current-vintage Joburg Market history, fixed Western Cape production "
        "assumptions and retrospective inflation adjustment; it does not show what "
        "information was published at the historical planting date.\n"
    )
    assert "using only data available at planting time" not in render_sentence(document)
    table = render_table(document)
    assert "retrospective fixed-2025-input simulation" in table
    for term in ("VAT", "calendar", "revision", "spinach", "late harvests", "CPI"):
        assert term in table


def test_retrospective_real_report_requires_observation_cutoff_evidence():
    with pytest.raises(ValueError, match="observation cutoff is not verified"):
        report(data_kind="historical")
    document = report(data_kind="historical", observation_cutoff_verified=True)
    assert document["information_policy"]["status"] == "verified_observation_cutoff_only"
    assert "retrospective fixed-2025-input" in render_sentence(document)
    assert "SYNTHETIC" not in render_sentence(document)


@pytest.mark.parametrize("field", ["information_cutoff_verified", "observation_cutoff_verified"])
def test_synthetic_cannot_attest_to_real_input_verification(field):
    with pytest.raises(ValueError, match="synthetic fixtures cannot claim"):
        report(**{field: True})


def test_retrospective_cannot_claim_strict_historical_availability():
    with pytest.raises(ValueError, match="cannot claim strict"):
        report(
            data_kind="historical",
            observation_cutoff_verified=True,
            information_cutoff_verified=True,
        )


def test_observation_cutoff_cannot_substitute_for_strict_verification():
    with pytest.raises(ValueError):
        build_report(
            ledger(),
            data_kind="historical",
            observation_cutoff_verified=True,
            input_hashes={"fabricated_fixture": "a" * 64},
        )


@pytest.mark.parametrize("gap", ["empty", "month", "crop", "key", "outside", "duplicate"])
def test_retrospective_real_report_retains_complete_grid_validation(gap):
    rows = ledger()
    invalid = {
        "empty": (),
        "month": rows[8:],
        "crop": tuple(row for row in rows if row.default != Crop.ONIONS),
        "key": rows[1:],
        "outside": rows + (replace(rows[0], origin=date(2025, 1, 1)),),
        "duplicate": rows + rows[:1],
    }[gap]
    with pytest.raises(ValueError, match="coverage|duplicate"):
        report(invalid, data_kind="historical", observation_cutoff_verified=True)


def test_skips_are_counted_without_fabricating_outcomes():
    rows = ledger()
    skipped = replace(
        rows[0], default_margin=None, recommended_margin=None, skip_reason="missing_realized_price"
    )
    document = report((skipped,) + rows[1:])
    assert document["results"]["pooled"]["skipped"] == 1
    assert "1247 scorable planting decisions" in render_sentence(document)


@pytest.mark.parametrize("renderer", [render_sentence, render_table])
@pytest.mark.parametrize("field", ["scenario", "status", "caveats"])
def test_retrospective_report_cannot_render_with_tampered_policy(renderer, field):
    document = report(data_kind="historical", observation_cutoff_verified=True)
    if field == "scenario":
        document["scenario"] = "strict_historical"
    elif field == "status":
        document["information_policy"]["status"] = "verified_strictly_before_planting"
    else:
        document["caveats"] = []
    with pytest.raises(ValueError, match="policy|caveats|information-cutoff"):
        renderer(document)


def test_synthetic_insufficient_evidence_still_carries_warning():
    rows = tuple(
        replace(row, recommended=row.default, recommended_margin=D(100)) for row in ledger()
    )
    sentence = render_sentence(report(rows))
    assert sentence.startswith("SYNTHETIC TEST FIXTURE — NOT A REAL RESULT.")
    assert "INSUFFICIENT EVIDENCE" in sentence


def test_synthetic_writer_cannot_publish_real_retrospective_report(tmp_path):
    document = report(data_kind="historical", observation_cutoff_verified=True)
    with pytest.raises(ValueError, match="only synthetic fixtures"):
        write_synthetic_report(document, tmp_path / "forbidden")
    assert not (tmp_path / "forbidden").exists()


def test_retrospective_synthetic_artifacts_are_deterministic_and_labelled(tmp_path):
    rows = ledger()[:16]
    left = tmp_path / "left"
    right = tmp_path / "right"
    assert write_synthetic_report(report(rows), left) == write_synthetic_report(
        report(tuple(reversed(rows))), right
    )
    assert {p.name: p.read_bytes() for p in left.iterdir()} == {
        p.name: p.read_bytes() for p in right.iterdir()
    }
    document = json.loads((left / "decision_backtest.json").read_bytes())
    assert document["data_kind"] == "synthetic"
    assert document["scenario"] == SCENARIO
    assert document["information_policy"]["status"] == "synthetic_not_applicable"


def test_invalid_synthetic_report_leaves_no_output_directory(tmp_path):
    document = report(ledger()[:8])
    document["scenario"] = "unregistered"
    with pytest.raises(ValueError, match="scenario"):
        write_synthetic_report(document, tmp_path / "invalid")
    assert not (tmp_path / "invalid").exists()
