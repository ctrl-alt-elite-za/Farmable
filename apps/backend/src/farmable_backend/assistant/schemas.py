from datetime import datetime
from typing import Annotated, Any, Literal
from uuid import UUID

from pydantic import Field, StrictInt

from farmable_backend.forecast_contract import Crop, Month
from farmable_backend.schemas import StrictModel


class ConversationCreate(StrictModel):
    id: UUID
    farm_id: UUID


class TurnCreate(StrictModel):
    id: UUID
    message: Annotated[str, Field(min_length=1, max_length=4000, pattern=r".*\S.*")]


class ConversationView(StrictModel):
    id: UUID
    farm_id: UUID
    created_at: datetime


class TurnView(StrictModel):
    id: UUID
    conversation_id: UUID
    status: Literal["running", "completed", "interrupted", "failed"]
    message: str
    reply: str
    tools: list[dict[str, Any]]
    error: str | None
    created_at: datetime
    deadline: datetime
    content_deleted_at: datetime | None
    # Admission reservation, NOT a claim about the provider's invoice.
    reserved_micro_usd: int
    usage: list[dict[str, int]]


class History(StrictModel):
    turns: list[TurnView]
    next_before: UUID | None


class SectionListArgs(StrictModel):
    limit: Annotated[StrictInt, Field(ge=1, le=20)] = 10


class OutlookArgs(StrictModel):
    section_id: UUID
    crop: Crop
    plant_month: Month


class StreamEvent(StrictModel):
    """Each SSE data object has this envelope; render text as plain text."""

    type: Literal["accepted", "text", "tool", "done", "error", "interrupted"]
    turn_id: UUID
    data: dict[str, Any]
