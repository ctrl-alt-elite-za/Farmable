"""Retrospective CPI reporting. This current-vintage file is not historical knowledge."""

import csv
import hashlib
import io
from dataclasses import dataclass
from datetime import date
from decimal import ROUND_HALF_EVEN, Context, Decimal, localcontext

from farmable_ml.data import decimal_value
from farmable_ml.money import reporting_value


@dataclass(frozen=True)
class CpiSeries:
    sha256: str
    observations: tuple[tuple[date, Decimal], ...]

    def index(self, month: date) -> Decimal:
        if month.day != 1:
            raise ValueError("CPI month must use day one")
        try:
            return dict(self.observations)[month]
        except KeyError as exc:
            raise ValueError(f"missing CPI month {month}") from exc

    def annual_mean(self, year: int) -> Decimal:
        with localcontext(Context(prec=28, rounding=ROUND_HALF_EVEN)):
            return (
                sum((self.index(date(year, month, 1)) for month in range(1, 13)), Decimal(0)) / 12
            )

    def to_2025(self, amount: Decimal, *, nominal_month: date) -> Decimal:
        """Convert a nominal amount once; do not pass already-2025 amounts here."""
        return reporting_value(
            amount, observation_cpi=self.index(nominal_month), reporting_cpi=self.annual_mean(2025)
        )


def read_cpi(content: bytes) -> CpiSeries:
    reader = csv.DictReader(io.StringIO(content.decode("utf-8-sig"), newline=""))
    if reader.fieldnames != ["observation_month", "index_dec2024_100"]:
        raise ValueError("expected Stats SA CPI index levels with Dec 2024=100")
    values = {}
    for row in reader:
        if None in row or any(value is None for value in row.values()):
            raise ValueError("malformed CPI row")
        month = date.fromisoformat(row["observation_month"])
        if month.day != 1 or month.isoformat() != row["observation_month"] or month in values:
            raise ValueError("CPI months must be unique YYYY-MM-01 dates")
        values[month] = decimal_value(row["index_dec2024_100"], "CPI index", positive=True)
    if not values:
        raise ValueError("empty CPI series")
    return CpiSeries(hashlib.sha256(content).hexdigest(), tuple(sorted(values.items())))
