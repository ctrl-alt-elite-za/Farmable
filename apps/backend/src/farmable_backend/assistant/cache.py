"""Opt-in Gemini explicit caching of STATIC instructions/tools only, never farm data."""

import asyncio
import hashlib
import json
import re
import time
from contextlib import suppress
from datetime import UTC, datetime

import httpx

from farmable_backend.assistant import accounting
from farmable_backend.integrations.base import Adapter

ROOT = "https://generativelanguage.googleapis.com/v1beta/"
STATIC = ("systemInstruction", "tools", "toolConfig")


class ContextCache:
    def __init__(self, registry):
        self.adapter = Adapter(
            "gemini", registry.client, registry.gemini.settings, timeout=10, max_attempts=1
        )
        self.lock = asyncio.Lock()
        self.name, self.key, self.expires, self.retry_after = None, None, 0.0, 0.0

    def headers(self):
        return {"x-goog-api-key": self.adapter.secret(self.adapter.settings.gemini_api_key)}

    async def invalidate(self):
        name, self.name = self.name, None
        self.key, self.expires = None, 0.0
        if name is not None:
            # Only a validated fixed-host resource name can reach this path.
            with suppress(Exception):
                await self.adapter.call(
                    httpx.Request("DELETE", ROOT + name, headers=self.headers())
                )

    async def apply(self, payload, store, worker, call_id, model):
        policy, today = store.policy.text_pricing, datetime.now(UTC).date()
        if (
            not store.policy.cache_enabled
            or policy is None
            or policy.model != model
            or not policy.valid_from <= today <= policy.valid_until
            or policy.cache_write_micro_usd_per_million is None
            or policy.cache_storage_micro_usd_per_million_token_hours is None
            or payload["toolConfig"]["functionCallingConfig"]["mode"] != "AUTO"
            or not self.adapter.secret(self.adapter.settings.gemini_api_key)
        ):
            return payload
        static = {key: payload[key] for key in STATIC}
        ttl = store.policy.cache_ttl_seconds
        key = hashlib.sha256(
            json.dumps([model, static, policy.fingerprint(), ttl], sort_keys=True).encode()
        ).hexdigest()

        async def note(mode, cost):
            await worker.call(accounting.note_cache, store.sessions, call_id, mode, cost)

        async with self.lock:
            if self.name is not None and (self.key != key or time.monotonic() >= self.expires):
                await self.invalidate()
            if self.name is not None:
                await note("reused", 0)
            else:
                if time.monotonic() < self.retry_after:
                    await note("bypassed", 0)
                    return payload
                self.retry_after = time.monotonic() + ttl
                # Persist ambiguity BEFORE the network request. Cancellation or a
                # crash cannot make an accepted cache creation look free.
                await note("creating", None)
                result = await self.adapter.call(
                    httpx.Request(
                        "POST",
                        ROOT + "cachedContents",
                        headers=self.headers(),
                        json={**static, "model": "models/" + model, "ttl": f"{ttl}s"},
                    )
                )
                if not result.ok:
                    # A definitive rejection did not create a cache. Timeouts,
                    # server failures and malformed replies remain unknown-cost.
                    rejected = (
                        result.status in {400, 401, 403, 404, 429} or result.error == "unavailable"
                    )
                    await note("unavailable", 0 if rejected else None)
                    return payload
                data = result.data or {}
                try:
                    name = data["name"]
                    tokens = data["usageMetadata"]["totalTokenCount"]
                    expiry = datetime.fromisoformat(data["expireTime"].replace("Z", "+00:00"))
                    if (
                        not isinstance(name, str)
                        or not re.fullmatch(r"cachedContents/[a-zA-Z0-9_-]{1,200}", name)
                        or data.get("model") != "models/" + model
                        or type(tokens) is not int
                        or not 0 <= tokens <= policy.max_prompt_tokens
                        or expiry.tzinfo is None
                    ):
                        raise ValueError("invalid_cache")
                    remaining = (expiry - datetime.now(UTC)).total_seconds()
                    if not 0 < remaining <= ttl + 5:
                        raise ValueError("invalid_cache_expiry")
                except (KeyError, TypeError, ValueError, AttributeError):
                    await note("unavailable", None)
                    return payload
                # Charge the entire requested TTL conservatively, even if deleted
                # early. This is a reviewed-rate estimate, not a provider invoice.
                numerator = tokens * (
                    policy.cache_write_micro_usd_per_million * 3600
                    + ttl * policy.cache_storage_micro_usd_per_million_token_hours
                )
                cost = (numerator + 3_600_000_000 - 1) // 3_600_000_000
                await note("created", cost)
                self.name, self.key = name, key
                self.expires = time.monotonic() + min(ttl, remaining) - 5
                self.retry_after = 0.0
            return {key: value for key, value in payload.items() if key not in STATIC} | {
                "cachedContent": self.name
            }

    async def close(self):
        async with self.lock:
            await self.invalidate()
        await self.adapter.release()

    async def discard(self, name):
        async with self.lock:
            if self.name == name:
                await self.invalidate()
