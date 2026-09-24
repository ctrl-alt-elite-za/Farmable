"""Canonical input and information-boundary tests use synthetic observations only."""

import hashlib
from datetime import date
from decimal import Decimal

import pytest
from farmable_ml.data import PRICE_COLUMNS, Crop, crop_id, observations_before, read_prices


def csv_bytes(*rows: str) -> bytes:
    return (",".join(PRICE_COLUMNS) + "\n" + "\n".join(rows) + "\n").encode()


def row(
    crop: str = "tomatoes",
    month: str = "2012-01-01",
    available: str = "2012-02-15",
    price: str = "3.50",
    market: str = "joburg",
) -> str:
    return f"{crop},{market},{month},{available},{price},{'a' * 64}"


def test_price_input_preserves_exact_bytes_hash_and_decimal():
    content = csv_bytes(row(), row(crop="cabbage"))
    result = read_prices(content)
    assert result.sha256 == hashlib.sha256(content).hexdigest()
    assert [record.crop for record in result.records] == [Crop.CABBAGE, Crop.TOMATOES]
    assert result.records[0].price_rand_per_kg == Decimal("3.50")
    assert read_prices(content.replace(b"\n", b"\r\n")).sha256 != result.sha256


def test_aliases_do_not_merge_combined_or_excluded_crops():
    assert crop_id(" Tomato ") == Crop.TOMATOES
    assert crop_id("green beans") == Crop.GREEN_BEANS
    for value in ("pumpkin_butternut", "pumpkins", "beetroot", "baby butternut"):
        with pytest.raises(ValueError, match="unknown or ambiguous"):
            crop_id(value)


@pytest.mark.parametrize("price", ["NaN", "Infinity", "-1", "0", "", "abc"])
def test_invalid_prices_fail_with_line_number(price):
    with pytest.raises(ValueError, match="line 2"):
        read_prices(csv_bytes(row(price=price)))


@pytest.mark.parametrize(
    ("month", "available"),
    [
        ("2012-01-02", "2012-02-15"),
        ("20120101", "2012-02-15"),
        ("2012-01-01", "2012-01-31"),
        ("2012-01-01", "2011-12-31"),
        ("2012-01-01", "2012-02-30"),
    ],
)
def test_invalid_months_and_availability_rejected(month, available):
    with pytest.raises(ValueError, match="line 2"):
        read_prices(csv_bytes(row(month=month, available=available)))


def test_duplicate_alias_and_conflicting_vintages_are_not_silently_overwritten():
    with pytest.raises(ValueError, match="duplicate"):
        read_prices(csv_bytes(row(), row(crop="tomato", price="9")))


def test_market_series_remain_distinct():
    result = read_prices(csv_bytes(row(), row(market="faostat_producer")))
    assert len(result.records) == 2


@pytest.mark.parametrize("content", [b"", csv_bytes(), csv_bytes(row() + ",extra")])
def test_empty_or_malformed_input_fails(content):
    with pytest.raises(ValueError):
        read_prices(content)


def test_strict_cutoff_uses_vintage_availability_not_observation_month():
    records = read_prices(
        csv_bytes(
            row(crop="cabbage", available="2012-02-28"),
            row(crop="carrots", available="2012-03-01"),
            row(crop="tomatoes", available="2020-01-01"),
        )
    ).records
    eligible = observations_before(records, date(2012, 3, 1))
    assert [record.crop for record in eligible] == [Crop.CABBAGE]
    with pytest.raises(ValueError, match="first day"):
        observations_before(records, date(2012, 3, 2))


def test_future_price_mutation_does_not_change_available_input():
    before = read_prices(csv_bytes(row(), row(crop="carrots", available="2013-01-01")))
    after = read_prices(csv_bytes(row(), row(crop="carrots", available="2013-01-01", price="999")))
    assert observations_before(before.records, date(2012, 3, 1)) == observations_before(
        after.records, date(2012, 3, 1)
    )
