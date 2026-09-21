"""Public record DTOs; never serialize ORM upload internals."""

from datetime import datetime
from decimal import Decimal
from typing import Annotated, Any, Generic, Literal, TypeVar
from uuid import UUID

from pydantic import (
    AwareDatetime,
    ConfigDict,
    Field,
    StrictBool,
    StrictInt,
    StringConstraints,
    field_validator,
)

from farmable_backend.record_access import utc
from farmable_backend.schemas import StrictModel

Short = Annotated[str, StringConstraints(strict=True, min_length=1, max_length=100, pattern=r"\S")]
Note = Annotated[str, StringConstraints(strict=True, min_length=1, max_length=10000, pattern=r"\S")]
OptionalShort = Annotated[str, StringConstraints(strict=True, max_length=100)]
OptionalNote = Annotated[str, StringConstraints(strict=True, max_length=10000)]


class ObservationCreate(StrictModel):
    mutation_id: UUID
    observation_id: UUID
    section_id: UUID
    type: Short
    note: Note
    health_status: OptionalShort | None = None
    action_taken: OptionalNote | None = None
    media_id: UUID | None = None
    created_by_voice: StrictBool = False
    created_at: AwareDatetime

    @field_validator("created_at", mode="before")
    @classmethod
    def timestamp_not_numeric(cls, value):
        if not isinstance(value, str | datetime):
            raise ValueError("ISO timestamp required")
        return value

    @field_validator("created_at")
    @classmethod
    def canonical_time(cls, value):
        return utc(value)


class UploadCreate(StrictModel):
    mutation_id: UUID
    local_media_id: UUID
    section_id: UUID
    content_type: Literal["image/jpeg", "image/png"]
    byte_length: Annotated[StrictInt, Field(ge=1, le=5_000_000)]


class RecordView(StrictModel):
    model_config = ConfigDict(extra="forbid", from_attributes=True)
    id: UUID
    owner_id: UUID
    version: int
    created_at: datetime
    updated_at: datetime

    @field_validator("created_at", "updated_at")
    @classmethod
    def canonical_time(cls, value):
        return utc(value)


class FarmView(RecordView):
    name: str


class SectionView(FarmView):
    farm_id: UUID
    boundary: dict[str, Any] | None
    area_m2: Decimal | None


class ObservationView(RecordView):
    farm_id: UUID
    section_id: UUID
    type: str
    note: str
    health_status: str | None
    action_taken: str | None
    media_id: UUID | None
    created_by_voice: bool


T = TypeVar("T")


class Page(StrictModel, Generic[T]):
    items: list[T]
    next_cursor: UUID | None


class ObservationAck(StrictModel):
    mutation_id: UUID
    entity_id: UUID
    owner_id: UUID
    farm_id: UUID
    version: int
    observation: ObservationView


class SignedForm(StrictModel):
    url: str = Field(repr=False)
    fields: dict[str, str] = Field(repr=False)
    expires_at: datetime

    @field_validator("expires_at")
    @classmethod
    def canonical_time(cls, value):
        return utc(value)


class UploadView(StrictModel):
    upload_id: UUID
    mutation_id: UUID
    entity_id: UUID
    owner_id: UUID
    farm_id: UUID
    state: Literal["awaiting_upload", "queued", "processing", "ready", "failed", "expired"]
    cloud_media_id: UUID | None = None
    error_code: str | None = None
    form: SignedForm | None = None
