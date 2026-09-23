"""Explicit, conversation-scoped permission; never infer it from model text."""

from datetime import datetime
from typing import Literal

from pydantic import Field

from farmable_backend.schemas import StrictModel

NOTICE_VERSION = "gemini-conversation-v1"
NOTICE = (
    "Allow this conversation's messages, recent replies and requested farm-section "
    "and crop-outlook data to be sent to Google Gemini to generate answers. "
    "Farmable stores conversation history until you delete your account; a separate "
    "automatic retention policy is not yet enabled. Provider retention depends on "
    "the operator's Google account terms. Withdrawing permission stops further "
    "generation but cannot recall data already sent or erase provider copies. "
    "Do not include sensitive personal information in messages."
)


class ConsentGrant(StrictModel):
    notice_version: Literal["gemini-conversation-v1"]
    model: str = Field(min_length=1, max_length=128)


class ConsentView(StrictModel):
    provider: Literal["google_gemini"] = "google_gemini"
    notice_version: str = NOTICE_VERSION
    notice: str = NOTICE
    model: str
    granted: bool
    granted_at: datetime | None
    withdrawn_at: datetime | None
