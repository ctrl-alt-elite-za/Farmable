"""Fail-closed operator policy, separate from provider credentials."""

import hashlib
from datetime import date

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict

from farmable_backend.assistant.pricing import TextPricePolicy


class AssistantSettings(BaseSettings):
    model_config = SettingsConfigDict(env_prefix="ASSISTANT_", extra="forbid")
    enabled: bool = False
    daily_budget_micro_usd: int = Field(default=0, ge=0, le=1_000_000_000)
    turn_reserve_micro_usd: int = Field(default=0, ge=0, le=100_000_000)
    policy_date: date | None = None
    policy_model: str = Field(default="", max_length=128)
    daily_turns_per_user: int = Field(default=20, ge=1, le=100)
    billing_project: str | None = Field(default=None, pattern=r"^[a-z][a-z0-9-]{4,61}[a-z0-9]$")
    text_pricing: TextPricePolicy | None = None
    cache_enabled: bool = False
    cache_ttl_seconds: int = Field(default=300, ge=60, le=600)

    def validate_live(self, today: date, model: str) -> None:
        # Reservation must cover ALL bounded model calls in a turn. Never infer
        # current provider prices or silently approve expenditure for an operator.
        if (
            not self.enabled
            or not 0 < self.turn_reserve_micro_usd <= self.daily_budget_micro_usd
            or self.policy_date is None
            or not 0 <= (today - self.policy_date).days <= 30
            or self.policy_model != model
        ):
            from farmable_backend.record_access import ApiError

            raise ApiError(503, "assistant_policy_required")

    def fingerprint(self) -> str:
        return hashlib.sha256(self.model_dump_json().encode()).hexdigest()
