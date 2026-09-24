"""Source inventories must not overstate the evidence in CSV blobs."""

import hashlib

import pytest
from inventory_issue20_data import canonical_crop, inventory_csv


def test_empty_csv_preserves_headers():
    blob = b"crop,year,month_num\n"
    result = inventory_csv("empty.csv", blob)
    assert result["columns"] == ["crop", "year", "month_num"]
    assert result["rows"] == 0
    assert result["sha256"] == hashlib.sha256(blob).hexdigest()


@pytest.mark.parametrize(
    "commodity",
    [
        "Carrots and turnips",
        "Onions and shallots, dry (excluding dehydrated)",
        "Pumpkins, squash and gourds",
        "Tomatoes: processing",
    ],
)
def test_combined_and_processing_commodities_do_not_prove_issue_crop_coverage(commodity):
    assert canonical_crop(commodity) not in {"carrots", "onions", "butternut", "tomatoes"}


@pytest.mark.parametrize("blob", [b"crop,crop\na,b\n", b"crop,year\na\n", b"crop\na,b\n"])
def test_malformed_csv_fails_explicitly(blob):
    with pytest.raises(ValueError, match="broken.csv"):
        inventory_csv("broken.csv", blob)


def test_wide_headers_do_not_claim_unpopulated_years():
    result = inventory_csv("wide.csv", b"Item,Y2024,Y2025\nCabbage,12,\n")
    assert result["coverage"]["wide_year_columns"] == {
        "min_year_with_values": 2024,
        "max_year_with_values": 2024,
        "nonempty_rows_by_year": {"2024": 1, "2025": 0},
    }
