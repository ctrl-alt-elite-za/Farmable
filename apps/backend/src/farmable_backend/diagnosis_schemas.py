"""No image bytes, object keys, provider payloads or credentials in public DTOs."""

from datetime import datetime
from typing import Annotated, Literal
from uuid import UUID

from pydantic import ConfigDict, Field, StringConstraints, field_validator

from farmable_backend.record_access import utc
from farmable_backend.schemas import StrictModel

NOTICE_VERSION = "crop-health-v1"
NOTICE = (
    "Submit this focus photo to Kindwise crop.health for suggested crop-health results. "
    "Only the cleaned photo is sent, not your name, location, or farm records. "
    "Results are suggestions, not a confirmed diagnosis or treatment prescription. "
    "Cancelling stops queued work and hides results but cannot erase a photo already sent "
    "to the provider. Results remain with your farm until cancelled or your account is deleted."
)


class DiagnosisCreate(StrictModel):
    id: UUID
    media_id: UUID
    planting_id: UUID
    consent_notice_version: Literal["crop-health-v1"]


class DiagnosisSuggestion(StrictModel):
    name: Annotated[str, StringConstraints(strict=True, min_length=1, max_length=200)]
    probability: Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]


class DiagnosisResult(StrictModel):
    provider: Literal["crop.health"] = "crop.health"
    schema_version: Literal[1] = 1
    data_kind: Literal["synthetic", "provider"]
    crop: DiagnosisSuggestion
    suggestions: Annotated[list[DiagnosisSuggestion], Field(min_length=1, max_length=5)]
    warning: str = "Provider suggestions only; not a confirmed diagnosis or treatment prescription."


class DiagnosisView(StrictModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)
    id: UUID
    farm_id: UUID
    section_id: UUID
    media_id: UUID
    planting_id: UUID
    crop: str
    state: Literal["queued", "processing", "ready", "unavailable", "cancelled"]
    error: str | None
    result: DiagnosisResult | None
    consent_notice_version: str
    created_at: datetime
    updated_at: datetime
    withdrawn_at: datetime | None

    @field_validator("created_at", "updated_at", "withdrawn_at")
    @classmethod
    def canonical_time(cls, value):
        return utc(value) if value is not None else None


class DiagnosisNotice(StrictModel):
    version: str = NOTICE_VERSION
    text: str = NOTICE
