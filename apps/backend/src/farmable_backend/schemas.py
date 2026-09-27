from datetime import datetime
from typing import Literal
from uuid import UUID

from pydantic import BaseModel, ConfigDict, EmailStr, Field


class StrictModel(BaseModel):
    """Base for every request DTO: unknown fields are errors."""

    model_config = ConfigDict(extra="forbid")


class Error(StrictModel):
    code: str
    message: str
    user_id: UUID | None = None


class ErrorResponse(StrictModel):
    error: Error


class LiveResponse(StrictModel):
    status: Literal["ok"] = "ok"
    sha: str


class ReadyResponse(StrictModel):
    database: Literal["ok", "down"]
    worker: Literal["ok", "down"]
    sha: str


class SignUpRequest(StrictModel):
    first_name: str = Field(min_length=1, max_length=100, pattern=r".*\S.*")
    surname: str = Field(min_length=1, max_length=100, pattern=r".*\S.*")
    phone: str = Field(pattern=r"^\+[1-9][0-9]{7,14}$")
    email: EmailStr
    password: str = Field(min_length=15, max_length=128, pattern=r".*\S.*")
    turnstile_token: str = Field(min_length=1, max_length=2048, repr=False)


class VerifyOtpRequest(StrictModel):
    user_id: UUID
    code: str = Field(pattern=r"^\d{6}$")


class ResendOtpRequest(StrictModel):
    user_id: UUID
    channel: Literal["phone", "email"]


class LoginRequest(StrictModel):
    identifier: str = Field(min_length=3, max_length=320)
    password: str = Field(min_length=1, max_length=128)
    turnstile_token: str = Field(min_length=1, max_length=2048, repr=False)


class RefreshRequest(StrictModel):
    refresh_token: str = Field(min_length=20, max_length=512)


class AuthProgressResponse(StrictModel):
    user_id: UUID
    next_step: Literal["phone", "email"]


class UserResponse(StrictModel):
    id: UUID
    first_name: str
    surname: str
    phone: str
    email: EmailStr
    phone_verified: bool
    email_verified: bool


class SessionResponse(StrictModel):
    access_token: str
    refresh_token: str
    expires_at: datetime
    refresh_expires_at: datetime
    user: UserResponse
