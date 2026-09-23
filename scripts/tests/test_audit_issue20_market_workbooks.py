"""Source audit must distinguish valid months from absent or inconsistent cells."""

import json
from pathlib import Path

import pytest
from audit_issue20_market_workbooks import ALIASES, audit_rows, json_payload

ROOT = Path(__file__).resolve().parents[2]


def workbook_rows(label_on_mass=False):
    rows = [["JOHANNESBURG 2024"], ["PRODUCT", "UNIT", *list("JFMAMJJASOND")]]
    for number, label in enumerate(ALIASES.values(), 1):
        rows.extend(
            [
                [f"{number}. {label}" if label_on_mass else "", "T", *([2.0] * 12)],
                ["" if label_on_mass else f"{number}. {label}", "R", *([100.0] * 12)],
                ["", "R/T", *([50.0] * 12)],
            ]
        )
    return rows


@pytest.mark.parametrize("label_on_mass", [False, True])
def test_recognizes_both_verified_product_row_layouts(label_on_mass):
    result = audit_rows(workbook_rows(label_on_mass), 2024)
    assert all(row["valid_months"] == list(range(1, 13)) for row in result.values())


def test_absent_zero_and_inconsistent_cells_do_not_count_as_coverage():
    rows = workbook_rows()
    rows[4][2] = None
    rows[4][3] = 0
    rows[4][4] = 70
    result = audit_rows(rows, 2024)["butternut"]
    assert result["missing_or_nonpositive_months"] == [1, 2]
    assert result["inconsistent_price_months"] == [3]
    assert result["valid_months"] == list(range(4, 13))


def test_wrong_year_and_duplicate_alias_fail():
    with pytest.raises(ValueError, match="market/year"):
        audit_rows(workbook_rows(), 2012)
    rows = workbook_rows()
    rows.extend(rows[2:5])
    with pytest.raises(ValueError, match="exactly one"):
        audit_rows(rows, 2024)


def test_committed_audit_fails_closed_when_release_dates_are_unknown():
    audit = json.loads((ROOT / "ml/data/market_workbook_audit.json").read_text())
    assert len(audit["sources"]) == 17
    for source in audit["sources"]:
        assert source["available_on"] is None
        assert source["availability_status"] == "unknown_blocks_historical_use"
        assert "not release evidence" in source["availability_evidence"]


def test_json_payload_keeps_month_arrays_reviewable_and_round_trips():
    document = {"months": list(range(1, 13)), "empty": [], "nested": {"year": 2024}}
    payload = json_payload(document)
    assert '"months": [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]' in payload
    assert json.loads(payload) == document
