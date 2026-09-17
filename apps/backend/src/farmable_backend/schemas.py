from typing import Literal

from pydantic import BaseModel, ConfigDict


class StrictModel(BaseModel):
    """Base for every request DTO: unknown fields are errors."""

    model_config = ConfigDict(extra="forbid")


class Error(StrictModel):
    code: str
    message: str


class ErrorResponse(StrictModel):
    error: Error


class LiveResponse(StrictModel):
    status: Literal["ok"] = "ok"
    sha: str


class ReadyResponse(StrictModel):
    database: Literal["ok", "down"]
    worker: Literal["ok", "down"]
    sha: str
