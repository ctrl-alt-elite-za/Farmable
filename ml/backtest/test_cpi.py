"""Reporting conversion against the checked-in, attributed Stats SA CPI series."""

from datetime import date
from decimal import Decimal as D
from pathlib import Path

import pytest
from build_issue20_cpi import build
from farmable_ml.cpi import read_cpi

DATA = Path(__file__).resolve().parents[1] / "data"


def test_cpi_adjustment():
    series = read_cpi((DATA / "cpi_za_monthly.csv").read_bytes())
    assert series.index(date(2012, 1, 1)) == D("53.0")
    # Sum the twelve published monthly levels, not the rounded annual-average cell.
    assert series.annual_mean(2025) == D("1229.9") / 12
    expected = D("100") * (D("1229.9") / 12) / D("53.0")
    assert series.to_2025(D("100"), nominal_month=date(2012, 1, 1)) == expected
    assert expected.quantize(D("0.01")) == D("193.38")


def test_cpi_csv_rebuilds_from_attributed_transcription():
    assert (
        build((DATA / "statssa_cpi_table_b1.txt").read_text(encoding="utf-8"))
        == (DATA / "cpi_za_monthly.csv").read_bytes()
    )


def test_reporting_base_requires_all_twelve_months():
    data = (DATA / "cpi_za_monthly.csv").read_bytes()
    truncated = b"\n".join(line for line in data.split(b"\n") if not line.startswith(b"2025-12"))
    with pytest.raises(ValueError, match="missing CPI month"):
        read_cpi(truncated).annual_mean(2025)
