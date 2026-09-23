"""Account and profile DTOs. Credentials and session material are never fields."""

from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import EmailStr, Field

from farmable_backend.schemas import StrictModel

# Keep this tuple in step with models.ACCOUNT_LANGUAGES; a test asserts they match.
Language = Literal["en", "af", "nso", "st", "xh", "zu"]

PHONE_PATTERN = r"^\+[1-9][0-9]{7,14}$"  # Same shape as SignUpRequest.phone (schemas.py).


class ProfileUpdate(StrictModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=100, pattern=r".*\S.*")
    surname: str | None = Field(default=None, min_length=1, max_length=100, pattern=r".*\S.*")
    preferred_language: Language | None = None
    # Changing either starts re-verification via ContactChangeRequest /
    # ContactChangeConfirm; the value here is never applied directly.
    email: EmailStr | None = None
    phone: str | None = Field(default=None, pattern=PHONE_PATTERN)


class ContactChangeConfirm(StrictModel):
    channel: Literal["phone", "email"]
    code: str = Field(min_length=1, max_length=32)


class FarmUpdate(StrictModel):
    name: str | None = Field(default=None, min_length=1, max_length=200, pattern=r".*\S.*")
    preferred_language: Language | None = None
    latitude: float | None = Field(default=None, ge=-90, le=90)
    longitude: float | None = Field(default=None, ge=-180, lt=180)


class DeleteAccountRequest(StrictModel):
    password: str = Field(min_length=1, max_length=128)


class ProfileResponse(StrictModel):
    id: UUID
    first_name: str
    surname: str
    phone: str
    email: EmailStr
    phone_verified: bool
    email_verified: bool
    preferred_language: Language
    # Non-null only while a requested email/phone change awaits its OTP.
    pending_email: EmailStr | None = None
    pending_phone: str | None = None


class AccountFarmResponse(StrictModel):
    id: UUID
    owner_id: UUID
    name: str
    preferred_language: Language
    latitude: float | None = None
    longitude: float | None = None


class ExportJobCreateResponse(StrictModel):
    id: UUID
    # Returned once, at creation, and never persisted or logged in the clear.
    download_token: str


class ExportJobStatusResponse(StrictModel):
    id: UUID
    status: Literal["pending", "ready", "failed", "expired"]
    format: Literal["json", "zip"]
    created_at: datetime
    expires_at: datetime | None = None
