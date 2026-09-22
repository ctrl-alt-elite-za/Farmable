"""Account and profile DTOs. Credentials and session material are never fields."""

from typing import Literal
from uuid import UUID

from pydantic import EmailStr, Field

from farmable_backend.schemas import StrictModel

# Keep this tuple in step with models.ACCOUNT_LANGUAGES; a test asserts they match.
Language = Literal["en", "af", "nso", "st", "xh", "zu"]


class ProfileUpdate(StrictModel):
    first_name: str | None = Field(default=None, min_length=1, max_length=100, pattern=r".*\S.*")
    surname: str | None = Field(default=None, min_length=1, max_length=100, pattern=r".*\S.*")
    preferred_language: Language | None = None


class FarmUpdate(StrictModel):
    name: str | None = Field(default=None, min_length=1, max_length=200, pattern=r".*\S.*")
    preferred_language: Language | None = None


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


class AccountFarmResponse(StrictModel):
    id: UUID
    owner_id: UUID
    name: str
    preferred_language: Language

"""
Email and phone are deliberately not updatable here: changing either would need a
fresh OTP verification round, which stays with the existing /auth/verify routes.
"""
