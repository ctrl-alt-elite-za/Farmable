"""Public record DTOs; never serialize ORM upload internals."""

from datetime import date as DateValue
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

from farmable_backend.photo_policy import PublicPhotoError
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


class UploadRetry(StrictModel):
    failed_attempt_id: UUID


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
    attempt_id: UUID
    retryable: bool
    mutation_id: UUID
    entity_id: UUID
    owner_id: UUID
    farm_id: UUID
    state: Literal["awaiting_upload", "queued", "processing", "ready", "failed", "expired"]
    cloud_media_id: UUID | None = None
    error_code: PublicPhotoError | None = None
    form: SignedForm | None = None


TaskStatus = Literal["pending", "in_progress", "done", "cancelled"]
FinancialType = Literal["expense", "income"]
PlanStatus = Literal["saved", "approved", "rejected"]
Version = Annotated[StrictInt, Field(ge=1)]
Cents = Annotated[StrictInt, Field(ge=0, le=1_000_000_000_000)]
Area = Annotated[Decimal, Field(gt=0, max_digits=14, decimal_places=2)]

EXAMPLE_MUTATION = "3f1d4b2a-0000-4000-8000-000000000001"
EXAMPLE_RECORD = "3f1d4b2a-0000-4000-8000-000000000002"
EXAMPLE_SECTION = "3f1d4b2a-0000-4000-8000-000000000003"


def examples(**fields: Any) -> ConfigDict:
    """One OpenAPI request example; StrictModel's extra="forbid" still applies."""
    return ConfigDict(json_schema_extra={"examples": [fields]})


class RecordDelete(StrictModel):
    model_config = examples(mutation_id=EXAMPLE_MUTATION, expected_version=1)

    mutation_id: UUID
    expected_version: Version | None = None


class SectionCreate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION, id=EXAMPLE_RECORD, name="North block", area_m2="1200.00"
    )

    mutation_id: UUID
    id: UUID
    name: Short
    boundary: dict[str, Any] | None = None
    area_m2: Area | None = None


class SectionUpdate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION, expected_version=1, name="North block", area_m2="1250.00"
    )

    mutation_id: UUID
    expected_version: Version
    name: Short
    boundary: dict[str, Any] | None = None
    area_m2: Area | None = None


class PlantingCreate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        id=EXAMPLE_RECORD,
        section_id=EXAMPLE_SECTION,
        crop="cabbage",
        planted_on="2026-08-01",
    )

    mutation_id: UUID
    id: UUID
    section_id: UUID
    crop: Short
    planted_on: DateValue | None = None
    is_current: StrictBool = True


class PlantingUpdate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION, expected_version=1, crop="tomato", planted_on="2026-08-02"
    )

    mutation_id: UUID
    expected_version: Version
    crop: Short
    planted_on: DateValue | None = None
    is_current: StrictBool = True


class ObservationUpdate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        expected_version=1,
        type="health",
        note="Leaves recovering",
        health_status="fair",
    )

    mutation_id: UUID
    expected_version: Version
    type: Short
    note: Note
    health_status: OptionalShort | None = None
    action_taken: OptionalNote | None = None


class TaskCreate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        id=EXAMPLE_RECORD,
        section_id=EXAMPLE_SECTION,
        title="Weed the beds",
        due_date="2026-10-01",
        status="pending",
        expected_cost_cents=1500,
    )

    mutation_id: UUID
    id: UUID
    section_id: UUID
    title: Short
    description: OptionalNote | None = None
    due_date: DateValue
    status: TaskStatus = "pending"
    expected_cost_cents: Cents | None = None


class TaskUpdate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        expected_version=1,
        title="Weed the beds",
        due_date="2026-10-02",
        status="done",
    )

    mutation_id: UUID
    expected_version: Version
    title: Short
    description: OptionalNote | None = None
    due_date: DateValue
    status: TaskStatus = "pending"
    expected_cost_cents: Cents | None = None


class FinancialCreate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        id=EXAMPLE_RECORD,
        section_id=EXAMPLE_SECTION,
        type="expense",
        category="seed",
        amount_cents=4200,
        date="2026-09-01",
    )

    mutation_id: UUID
    id: UUID
    section_id: UUID | None = None
    type: FinancialType
    category: Short
    amount_cents: Cents
    date: DateValue
    note: OptionalNote | None = None


class FinancialUpdate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        expected_version=1,
        type="income",
        category="sale",
        amount_cents=9900,
        date="2026-09-02",
    )

    mutation_id: UUID
    expected_version: Version
    type: FinancialType
    category: Short
    amount_cents: Cents
    date: DateValue
    note: OptionalNote | None = None


class PlanCreate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        id=EXAMPLE_RECORD,
        section_id=EXAMPLE_SECTION,
        status="saved",
        plan={"steps": []},
    )

    mutation_id: UUID
    id: UUID
    section_id: UUID
    status: PlanStatus = "saved"
    plan: dict[str, Any]


class PlanUpdate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION, expected_version=1, status="approved", plan={"steps": []}
    )

    mutation_id: UUID
    expected_version: Version
    status: PlanStatus = "saved"
    plan: dict[str, Any]


class MediaCreate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION,
        id=EXAMPLE_RECORD,
        section_id=EXAMPLE_SECTION,
        local_id="device-photo-1",
        media_type="image/png",
    )

    mutation_id: UUID
    id: UUID
    section_id: UUID | None = None
    local_id: Short
    media_type: Short


class MediaUpdate(StrictModel):
    model_config = examples(
        mutation_id=EXAMPLE_MUTATION, expected_version=1, media_type="image/jpeg"
    )

    mutation_id: UUID
    expected_version: Version
    section_id: UUID | None = None
    media_type: Short


class PlantingView(RecordView):
    farm_id: UUID
    section_id: UUID
    crop: str
    planted_on: DateValue | None
    is_current: bool


class TaskView(RecordView):
    farm_id: UUID
    section_id: UUID
    title: str
    description: str | None
    due_date: DateValue
    status: str
    expected_cost_cents: int | None


class FinancialView(RecordView):
    farm_id: UUID
    section_id: UUID | None
    type: str
    category: str
    amount_cents: int
    date: DateValue
    note: str | None


class PlanView(RecordView):
    farm_id: UUID
    section_id: UUID
    status: str
    plan: dict[str, Any]


class MediaView(RecordView):
    farm_id: UUID
    section_id: UUID | None
    local_id: str
    media_type: str


class RecordAck(StrictModel, Generic[T]):
    mutation_id: UUID
    entity_id: UUID
    owner_id: UUID
    farm_id: UUID
    version: int
    record: T


class ChangeView(StrictModel):
    cursor: int
    record_type: str
    record_id: UUID
    operation: str
    version: int
    created_at: datetime

    @field_validator("created_at")
    @classmethod
    def canonical_time(cls, value):
        return utc(value)


class ChangePage(StrictModel):
    items: list[ChangeView]
    next_cursor: int | None


class FinancialSummary(StrictModel):
    income_cents: int
    expense_cents: int
    net_cents: int


class SectionDetail(StrictModel):
    section: SectionView
    current_planting: PlantingView | None
    current_plan: PlanView | None
    latest_health_status: str | None
    observations: list[ObservationView]
    tasks: list[TaskView]
    financials: FinancialSummary
