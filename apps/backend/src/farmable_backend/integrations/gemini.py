from collections.abc import AsyncGenerator
from typing import Any

import httpx

from .base import Adapter, ServiceResult


def has_visible_text(payload: dict[str, Any]) -> bool:
    candidates = payload.get("candidates")
    if not isinstance(candidates, list):
        return False
    for candidate in candidates:
        content = candidate.get("content") if isinstance(candidate, dict) else None
        parts = content.get("parts") if isinstance(content, dict) else None
        if isinstance(parts, list) and any(
            isinstance(part, dict)
            and isinstance(part.get("text"), str)
            and bool(part["text"])
            and not part.get("thought", False)
            for part in parts
        ):
            return True
    return False


class Gemini(Adapter):
    def request(self, payload: dict[str, Any], *, streaming: bool) -> httpx.Request | None:
        key = self.secret(self.settings.gemini_api_key)
        model = (
            "fixture-model"
            if self.settings.integrations_mode == "fake"
            else self.settings.gemini_model
        )
        if not key or not model:
            return None
        method = "streamGenerateContent" if streaming else "generateContent"
        return httpx.Request(
            "POST",
            f"https://generativelanguage.googleapis.com/v1beta/models/{model}:{method}",
            headers={"x-goog-api-key": key},
            params={"alt": "sse"} if streaming else None,
            json=payload,
        )

    async def generate(self, payload: dict[str, Any]) -> ServiceResult:
        request = self.request(payload, streaming=False)
        return await self.call(request) if request is not None else self.failure("misconfigured")

    async def generate_stream(
        self,
        payload: dict[str, Any],
        *,
        first_text_timeout: float = 10,
    ) -> AsyncGenerator[ServiceResult, None]:
        request = self.request(payload, streaming=True)
        if request is None:
            yield self.failure("misconfigured", done=True)
            return
        iterator = self.stream(
            request, first_text_timeout=first_text_timeout, has_text=has_visible_text
        )
        try:
            async for event in iterator:
                yield event
        finally:
            await iterator.aclose()
