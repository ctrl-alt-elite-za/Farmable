"""Validate complete reference bundles, then import them atomically through the ORM."""

import hashlib
from datetime import date
from decimal import Decimal
from typing import Annotated, Any, Literal

from pydantic import BaseModel, ConfigDict, Field, TypeAdapter, field_validator, model_validator
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from farmable_backend.models import (
    ReferenceCropCalendar,
    ReferenceCropCost,
    ReferenceImport,
    ReferenceMarketPrice,
)

MAX_REFERENCE_BUNDLE_BYTES = 16 * 1024 * 1024
CropId = Literal[
    "butternut", "cabbage", "carrots", "green_beans", "onions", "potatoes", "spinach", "tomatoes"
]


class StrictModel(BaseModel):
    model_config = ConfigDict(extra="forbid", frozen=True)


class MarketPriceRow(StrictModel):
    crop: CropId
    market: str = Field(min_length=1, max_length=100)
    observation_month: date
    available_on: date
    price_rand_per_kg: Decimal = Field(gt=0, max_digits=14, decimal_places=4)
    availability_kind: Literal["publication", "analytical_next_month"]

    @model_validator(mode="after")
    def dates_are_monthly_and_available(self):
        month = self.observation_month
        next_month = date(month.year + (month.month == 12), month.month % 12 + 1, 1)
        if month.day != 1 or self.available_on < next_month:
            raise ValueError("market price dates are invalid")
        if self.availability_kind == "analytical_next_month" and self.available_on != next_month:
            raise ValueError("analytical availability must be the following month")
        return self


class CalendarRow(StrictModel):
    crop: CropId
    region: str = Field(min_length=1, max_length=100)
    effective_on: date
    available_on: date
    revision: int = Field(gt=0)
    planting_months: list[int] = Field(min_length=1, max_length=12)
    harvest_offset_months: int = Field(ge=1, le=12)
    yield_kg_per_ha: Decimal = Field(gt=0, max_digits=14, decimal_places=4)
    assumption_kind: Literal["fixed_scenario", "historical_vintage"]

    @model_validator(mode="after")
    def availability_follows_effective_date(self):
        if self.available_on < self.effective_on:
            raise ValueError("calendar availability predates its effective date")
        return self

    @field_validator("planting_months")
    @classmethod
    def months_are_unique(cls, value: list[int]) -> list[int]:
        if value != sorted(set(value)) or any(not 1 <= month <= 12 for month in value):
            raise ValueError("planting months must be sorted unique values in 1..12")
        return value


class CostRow(StrictModel):
    crop: CropId
    region: str = Field(min_length=1, max_length=100)
    effective_on: date
    available_on: date
    revision: int = Field(gt=0)
    basis_year: int = Field(ge=1900, le=2100)
    cost_rand_per_ha: Decimal = Field(ge=0, max_digits=14, decimal_places=4)
    marketing_rate: Decimal = Field(ge=0, lt=1, max_digits=8, decimal_places=6)
    vat_basis: Literal["included", "excluded", "unstated"]

    @model_validator(mode="after")
    def availability_follows_effective_date(self):
        if self.available_on < self.effective_on:
            raise ValueError("cost availability predates its effective date")
        return self


class BundleBase(StrictModel):
    schema_version: Literal[1]
    dataset_key: str = Field(pattern=r"^[a-z0-9][a-z0-9_.-]{0,99}$")
    source_sha256: str = Field(pattern=r"^[0-9a-f]{64}$")
    source_file: str = Field(min_length=1, max_length=255, pattern=r"^[^/\\\x00-\x1f]+$")
    parser_version: int = Field(gt=0)


class MarketBundle(BundleBase):
    dataset_kind: Literal["market_prices"]
    rows: list[MarketPriceRow] = Field(min_length=1, max_length=10000)


class CalendarBundle(BundleBase):
    dataset_kind: Literal["crop_calendars"]
    rows: list[CalendarRow] = Field(min_length=1, max_length=100)


class CostBundle(BundleBase):
    dataset_kind: Literal["crop_costs"]
    rows: list[CostRow] = Field(min_length=1, max_length=100)


ReferenceBundle = Annotated[
    MarketBundle | CalendarBundle | CostBundle, Field(discriminator="dataset_kind")
]
ADAPTER: TypeAdapter[ReferenceBundle] = TypeAdapter(ReferenceBundle)


def parse_bundle(raw: bytes) -> ReferenceBundle:
    if not raw or len(raw) > MAX_REFERENCE_BUNDLE_BYTES:
        raise ValueError("reference bundle has invalid size")
    bundle = ADAPTER.validate_json(raw)
    keys: list[tuple[Any, ...]] = []
    for row in bundle.rows:
        if isinstance(row, MarketPriceRow):
            keys.append((row.crop, row.market, row.observation_month))
        elif isinstance(row, CalendarRow):
            keys.append((row.crop, row.region, row.effective_on, row.revision))
        else:
            keys.append((row.crop, row.region, row.effective_on, row.revision))
    if len(keys) != len(set(keys)):
        raise ValueError("reference bundle contains duplicate natural keys")
    return bundle


def import_bundle(sessions, raw: bytes) -> tuple[str, int]:
    """Return status and row count; identical bytes are a no-op, conflicts fail closed."""
    bundle = parse_bundle(raw)  # Validate the entire document before opening a transaction.
    payload_sha256 = hashlib.sha256(raw).hexdigest()
    try:
        return _import_validated(sessions, bundle, payload_sha256)
    except IntegrityError as exc:
        # A concurrent identical importer can win the unique dataset key. Its
        # transaction has committed before the constraint failure is returned.
        # Re-read in a fresh transaction after rolling back every attempted row.
        with sessions() as session:
            existing = session.scalar(
                select(ReferenceImport).where(
                    ReferenceImport.dataset_kind == bundle.dataset_kind,
                    ReferenceImport.dataset_key == bundle.dataset_key,
                )
            )
            if existing is not None and (
                existing.source_sha256,
                existing.payload_sha256,
                existing.parser_version,
            ) == (bundle.source_sha256, payload_sha256, bundle.parser_version):
                return "unchanged", existing.row_count
        raise ValueError("reference dataset identity or natural key conflict") from exc


def _import_validated(sessions, bundle: ReferenceBundle, payload_sha256: str) -> tuple[str, int]:
    with sessions.begin() as session:
        existing = session.scalar(
            select(ReferenceImport).where(
                ReferenceImport.dataset_kind == bundle.dataset_kind,
                ReferenceImport.dataset_key == bundle.dataset_key,
            )
        )
        if existing is not None:
            identity = (existing.source_sha256, existing.payload_sha256, existing.parser_version)
            if identity != (bundle.source_sha256, payload_sha256, bundle.parser_version):
                raise ValueError("reference dataset identity conflict")
            return "unchanged", existing.row_count
        imported = ReferenceImport(
            dataset_kind=bundle.dataset_kind,
            dataset_key=bundle.dataset_key,
            source_file=bundle.source_file,
            source_sha256=bundle.source_sha256,
            payload_sha256=payload_sha256,
            parser_version=bundle.parser_version,
            row_count=len(bundle.rows),
        )
        session.add(imported)
        session.flush()
        if isinstance(bundle, MarketBundle):
            session.add_all(
                ReferenceMarketPrice(import_id=imported.id, **row.model_dump())
                for row in bundle.rows
            )
        elif isinstance(bundle, CalendarBundle):
            session.add_all(
                ReferenceCropCalendar(import_id=imported.id, **row.model_dump())
                for row in bundle.rows
            )
        else:
            session.add_all(
                ReferenceCropCost(import_id=imported.id, **row.model_dump()) for row in bundle.rows
            )
        session.flush()
        return "imported", len(bundle.rows)
