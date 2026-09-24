"""Strict canonical price input contract; source-specific adapters remain separate.

Prices are nominal ZAR/kg observations. These records cannot be substituted for
an inflation-adjusted forecast or a deployment snapshot. Availability describes
this exact observation vintage, not merely the month to which the value relates.
"""

import csv
import hashlib
import io
import re
from dataclasses import dataclass
from datetime import date
from decimal import Decimal, InvalidOperation
from enum import StrEnum


class Crop(StrEnum):
    BUTTERNUT = "butternut"
    CABBAGE = "cabbage"
    CARROTS = "carrots"
    GREEN_BEANS = "green_beans"
    ONIONS = "onions"
    POTATOES = "potatoes"
    SPINACH = "spinach"
    TOMATOES = "tomatoes"


class ObservationPolicy(StrEnum):
    PUBLICATION = "published_before_planting"
    RETROSPECTIVE = "observation_before_planting"


EXCLUDED = {
    "beetroot": "No cost budget in the issue's included crop set.",
    "pumpkins": "No cost budget in the issue's included crop set.",
}

_ALIASES = {crop.value: crop for crop in Crop} | {
    "carrot": Crop.CARROTS,
    "green beans": Crop.GREEN_BEANS,
    "green bean": Crop.GREEN_BEANS,
    "onion": Crop.ONIONS,
    "potato": Crop.POTATOES,
    "tomato": Crop.TOMATOES,
}

PRICE_COLUMNS = (
    "crop",
    "market",
    "observation_month",
    "available_on",
    "price_rand_per_kg",
    "source_sha256",
)


def crop_id(value: str) -> Crop:
    """Resolve documented spelling aliases only; never split combined commodities."""
    try:
        return _ALIASES[value.strip().lower()]
    except KeyError as exc:
        raise ValueError(f"unknown or ambiguous crop: {value!r}") from exc


def decimal_value(value: str, field: str, *, positive: bool = False) -> Decimal:
    try:
        result = Decimal(value)
    except InvalidOperation as exc:
        raise ValueError(f"{field} must be a finite decimal") from exc
    if not result.is_finite() or result < 0 or (positive and result == 0):
        requirement = "positive" if positive else "nonnegative"
        raise ValueError(f"{field} must be finite and {requirement}")
    return result


def _iso_date(value: str, field: str) -> date:
    if not re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        raise ValueError(f"{field} must use YYYY-MM-DD")
    try:
        return date.fromisoformat(value)
    except ValueError as exc:
        raise ValueError(f"{field} is not a valid date") from exc


@dataclass(frozen=True)
class PriceObservation:
    crop: Crop
    market: str
    observation_month: date
    available_on: date
    price_rand_per_kg: Decimal
    source_sha256: str
    availability_kind: str = "publication"

    def __post_init__(self) -> None:
        if self.availability_kind not in {"publication", "analytical_next_month"}:
            raise ValueError("unknown availability kind")
        if self.availability_kind == "analytical_next_month":
            year, month = divmod(
                self.observation_month.year * 12 + self.observation_month.month, 12
            )
            if self.available_on != date(year, month + 1, 1):
                raise ValueError("analytical availability must be the first day of the next month")
        if not isinstance(self.crop, Crop):
            raise ValueError("crop must be a canonical Crop")
        if not self.market.strip() or self.market != self.market.strip():
            raise ValueError("market must be a nonempty, trimmed identifier")
        if self.observation_month.day != 1:
            raise ValueError("observation_month must be the first day of its month")
        # A finalized monthly observation cannot be available within that month.
        if (self.available_on.year, self.available_on.month) <= (
            self.observation_month.year,
            self.observation_month.month,
        ):
            raise ValueError("available_on must follow the observation month")
        if not isinstance(self.price_rand_per_kg, Decimal):
            raise ValueError("price_rand_per_kg must be a Decimal")
        decimal_value(str(self.price_rand_per_kg), "price_rand_per_kg", positive=True)
        if not re.fullmatch(r"[0-9a-f]{64}", self.source_sha256):
            raise ValueError("source_sha256 must be a lowercase SHA-256 digest")


@dataclass(frozen=True)
class PriceInput:
    """The exact canonical CSV hash and its sorted, unique records."""

    sha256: str
    records: tuple[PriceObservation, ...]


def read_prices(content: bytes) -> PriceInput:
    """Read canonical UTF-8 CSV; reject duplicates, extra columns and invalid rows.

    Source adapters must resolve duplicate observations/revisions explicitly
    before producing this single-vintage input. No silent last-row-wins policy.
    """
    try:
        decoded = content.decode("utf-8-sig")
    except UnicodeDecodeError as exc:
        raise ValueError("price CSV must be UTF-8") from exc
    reader = csv.DictReader(io.StringIO(decoded, newline=""))
    if reader.fieldnames is None or tuple(reader.fieldnames) != PRICE_COLUMNS:
        raise ValueError(f"price CSV columns must be exactly {','.join(PRICE_COLUMNS)}")
    records = []
    keys: set[tuple[Crop, str, date]] = set()
    for row in reader:
        try:
            if None in row or any(value is None for value in row.values()):
                raise ValueError("wrong number of fields")
            record = PriceObservation(
                crop=crop_id(row["crop"]),
                market=row["market"],
                observation_month=_iso_date(row["observation_month"], "observation_month"),
                available_on=_iso_date(row["available_on"], "available_on"),
                price_rand_per_kg=decimal_value(
                    row["price_rand_per_kg"], "price_rand_per_kg", positive=True
                ),
                source_sha256=row["source_sha256"],
            )
            key = (record.crop, record.market, record.observation_month)
            if key in keys:
                raise ValueError("duplicate crop/market/observation_month")
            keys.add(key)
            records.append(record)
        except ValueError as exc:
            raise ValueError(f"price CSV line {reader.line_num}: {exc}") from exc
    if not records:
        raise ValueError("price CSV contains no observations")
    return PriceInput(
        sha256=hashlib.sha256(content).hexdigest(),
        records=tuple(sorted(records, key=lambda r: (r.crop, r.market, r.observation_month))),
    )


def observations_before(
    records: tuple[PriceObservation, ...],
    cutoff: date,
    *,
    policy: ObservationPolicy = ObservationPolicy.PUBLICATION,
) -> tuple[PriceObservation, ...]:
    """Apply the requested publication or analytical observation cutoff."""
    if cutoff.day != 1:
        raise ValueError("planting cutoff must be the first day of a month")
    if not isinstance(policy, ObservationPolicy):
        raise ValueError("an explicit supported observation policy is required")
    if policy is ObservationPolicy.RETROSPECTIVE:
        return tuple(record for record in records if record.observation_month < cutoff)
    return tuple(record for record in records if record.available_on < cutoff)
