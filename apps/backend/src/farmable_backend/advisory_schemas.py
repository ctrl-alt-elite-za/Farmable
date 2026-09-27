"""Farm profile and source-backed funding/procurement DTOs."""

from datetime import date, datetime
from decimal import Decimal
from typing import Literal
from uuid import UUID

from pydantic import Field

from farmable_backend.schemas import StrictModel


class FarmProfileUpdate(StrictModel):
    province: str | None = Field(default=None, max_length=100)
    municipality: str | None = Field(default=None, max_length=160)
    farmer_type: str | None = Field(default=None, max_length=80)
    business_status: str | None = Field(default=None, max_length=80)
    farm_size_ha: Decimal | None = Field(default=None, gt=0, max_digits=14, decimal_places=2)
    annual_turnover_band: str | None = Field(default=None, max_length=40)
    crops: list[str] = Field(default_factory=list, max_length=30)
    goals: list[str] = Field(default_factory=list, max_length=30)
    equipment: list[str] = Field(default_factory=list, max_length=30)


class FarmProfileView(FarmProfileUpdate):
    farm_id: UUID
    owner_id: UUID
    updated_at: datetime | None


class AdvisoryMatch(StrictModel):
    id: UUID
    kind: Literal["funding", "procurement"]
    name: str
    provider: str
    summary: str
    match_reasons: list[str]
    missing_profile_fields: list[str]
    opens_on: date | None
    closes_on: date | None
    deadline_note: str
    source_url: str
    application_url: str | None
    verified_on: date
    strategy_steps: list[str]
