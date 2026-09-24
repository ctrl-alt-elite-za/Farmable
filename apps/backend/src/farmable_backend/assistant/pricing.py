"""Versioned operator rates for text calls. Estimates are never provider invoices."""

import hashlib
from datetime import date
from typing import Annotated

from pydantic import Field, StrictInt, model_validator

from farmable_backend.schemas import StrictModel

Rate = Annotated[StrictInt, Field(ge=0, le=1_000_000_000)]
ModelName = Annotated[str, Field(pattern=r"^[a-zA-Z0-9._-]{1,128}$")]


class TextPricePolicy(StrictModel):
    model: ModelName
    response_models: Annotated[list[ModelName], Field(min_length=1, max_length=10)]
    valid_from: date
    valid_until: date
    # USD micro-units per million tokens, not binary floating-point prices.
    input_micro_usd_per_million: Rate
    cached_input_micro_usd_per_million: Rate
    output_micro_usd_per_million: Rate
    max_prompt_tokens: Annotated[StrictInt, Field(ge=1, le=10_000_000)]
    cache_write_micro_usd_per_million: Rate | None = None
    cache_storage_micro_usd_per_million_token_hours: Rate | None = None

    @model_validator(mode="after")
    def bounded_policy(self):
        if not 0 <= (self.valid_until - self.valid_from).days <= 30:
            raise ValueError("Pricing policy must cover at most 31 calendar days")
        return self

    def fingerprint(self):
        return hashlib.sha256(self.model_dump_json().encode()).hexdigest()


def price_usage(policy, model, response_model, day, usage, *, complete):
    """Ceil once per exchange; refuse partial, tier-mismatched or unexplained usage."""
    if not complete:
        return None, "incomplete_exchange"
    if policy is None:
        return None, "pricing_not_configured"
    if model != policy.model or response_model not in policy.response_models:
        return None, "pricing_model_mismatch"
    if not policy.valid_from <= day <= policy.valid_until:
        return None, "pricing_out_of_date"
    required = {"promptTokenCount", "candidatesTokenCount", "totalTokenCount"}
    if not required <= usage.keys():
        return None, "usage_missing"
    if any(type(value) is not int or not 0 <= value <= 10_000_000 for value in usage.values()):
        return None, "usage_invalid"
    prompt, output = usage["promptTokenCount"], usage["candidatesTokenCount"]
    thoughts, cached = usage.get("thoughtsTokenCount", 0), usage.get("cachedContentTokenCount", 0)
    if cached > prompt or usage["totalTokenCount"] != prompt + output + thoughts:
        return None, "usage_inconsistent"
    if prompt > policy.max_prompt_tokens:
        return None, "pricing_tier_exceeded"
    numerator = (
        (prompt - cached) * policy.input_micro_usd_per_million
        + cached * policy.cached_input_micro_usd_per_million
        + (output + thoughts) * policy.output_micro_usd_per_million
    )
    return (numerator + 999_999) // 1_000_000, None
