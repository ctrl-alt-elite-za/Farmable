"""Single-use Gemini Live credentials, never general-purpose API keys."""

import re
import threading
from copy import deepcopy
from datetime import UTC, datetime, timedelta

import httpx

from .base import Adapter, ProviderFailure, ServiceResult


class GeminiLive(Adapter):
    def __init__(self, client, settings):
        # Minting is not idempotent. Never retry an ambiguous provider response.
        super().__init__("gemini", client, settings, timeout=10, max_attempts=1)
        self.slots = threading.BoundedSemaphore(4)

    @property
    def configured(self) -> bool:
        return bool(
            self.settings.gemini_live_enabled
            and self.settings.integrations_mode != "disabled"
            and self.settings.gemini_live_model
            and self.secret(self.settings.gemini_api_key)
        )

    async def response(self, request: httpx.Request, binary: bool) -> ServiceResult:
        result = await super().response(request, binary)
        name = (result.data or {}).get("name")
        key = request.headers["x-goog-api-key"]
        if (
            not isinstance(name, str)
            or re.fullmatch(r"auth_tokens/[!-~]{1,8192}", name) is None
            or key in name
        ):
            raise ProviderFailure("invalid_response")
        # All other provider fields are discarded, including unexpected secrets.
        return ServiceResult(self.service, True, data={"credential": name})

    async def issue(self, *, setup: dict | None = None) -> ServiceResult:
        if not self.configured:
            return self.failure("disabled")
        if not self.slots.acquire(blocking=False):
            return self.failure("capacity")
        try:
            now = datetime.now(UTC)
            expires = now + timedelta(minutes=10)
            connect_by = now + timedelta(seconds=60)
            model = f"models/{self.settings.gemini_live_model}"
            # Only server callers can supply this policy. Never forward HTTP body
            # fields here; an explicit setup is locked in full by the token.
            if setup is not None and setup.get("model") != model:
                return self.failure("invalid_setup")
            request = self.client.build_request(
                "POST",
                "https://generativelanguage.googleapis.com/v1beta/auth_tokens",
                headers={"x-goog-api-key": self.secret(self.settings.gemini_api_key) or ""},
                json={
                    "uses": 1,
                    "expireTime": expires.isoformat(),
                    "newSessionExpireTime": connect_by.isoformat(),
                    # REST discovery schema, not the SDK's liveConnectConstraints wrapper.
                    # Empty fieldMask locks the entire setup: no client tools/overrides.
                    "bidiGenerateContentSetup": deepcopy(setup)
                    if setup is not None
                    else {
                        "model": model,
                        "generationConfig": {"responseModalities": ["AUDIO"]},
                        "sessionResumption": {},
                    },
                },
            )
            result = await self.call(request)
            if not result.ok:
                return result
            return ServiceResult(
                self.service,
                True,
                data={
                    **(result.data or {}),
                    "expires_at": expires,
                    "new_session_expires_at": connect_by,
                    "model": model,
                    "api_version": "v1beta",
                    "mode": self.settings.integrations_mode,
                },
            )
        finally:
            self.slots.release()
