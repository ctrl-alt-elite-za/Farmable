"""Isolated fake HTTP transport: no socket, credential, or live-network fallback."""

import asyncio
import io
import json
import wave
from collections import Counter
from datetime import date, timedelta
from importlib.resources import files
from typing import Any, Literal

import httpx

from .settings import SERVICES

FakeMode = Literal["success", "error", "slow"]


def example_audio() -> bytes:
    buffer = io.BytesIO()
    with wave.open(buffer, "wb") as audio:
        audio.setnchannels(1)
        audio.setsampwidth(2)
        audio.setframerate(16000)
        audio.writeframes(b"\x00\x00" * 16000)
    return buffer.getvalue()


def examples() -> dict[str, Any]:
    return json.loads(files(__package__).joinpath("fixtures/provider_examples.json").read_text())


class FakeTransport(httpx.AsyncBaseTransport):
    def __init__(self, modes: dict[str, FakeMode] | None = None, *, slow_delay: float = 120):
        self.modes = modes or {}
        if any(
            service not in SERVICES or mode not in {"success", "error", "slow"}
            for service, mode in self.modes.items()
        ):
            raise ValueError("Unknown fake service or mode")
        self.slow_delay = slow_delay
        self.calls: Counter[str] = Counter()
        self.fixtures = examples()

    @staticmethod
    def service(request: httpx.Request) -> str:
        hosts = {
            "verify.twilio.com": "twilio",
            "challenges.cloudflare.com": "turnstile",
            "fixture.cognitiveservices.azure.com": "azure_stt",
            "southafricanorth.tts.speech.microsoft.com": "azure_tts",
            "generativelanguage.googleapis.com": "gemini",
            "crop.kindwise.com": "crop_health",
            "rest.isric.org": "soilgrids",
            "api.open-meteo.com": "open_meteo",
            "archive-api.open-meteo.com": "open_meteo",
            "geocode.googleapis.com": "maps",
        }
        service = hosts.get(request.url.host)
        if service is None:
            raise ValueError("Fake transport refuses unknown endpoint")
        return service

    async def handle_async_request(self, request: httpx.Request) -> httpx.Response:
        service = self.service(request)
        self.calls[service] += 1
        mode = self.modes.get(service, "success")
        if mode == "slow":
            await asyncio.sleep(self.slow_delay)
        if mode == "error":
            return httpx.Response(503, json=self.fixtures["error"])
        if service == "azure_tts":
            return httpx.Response(
                200, content=example_audio(), headers={"content-type": "audio/wav"}
            )
        payload = self.fixtures["success"][service]
        if service == "open_meteo" and request.url.path == "/v1/archive":
            start = date.fromisoformat(request.url.params["start_date"])
            end = date.fromisoformat(request.url.params["end_date"])
            count = (end - start).days + 1
            if not 1 <= count <= 6201:
                return httpx.Response(400, json={"error": True})
            return httpx.Response(
                200,
                json={
                    "daily_units": {
                        "temperature_2m_min": "°C",
                        "temperature_2m_max": "°C",
                        "precipitation_sum": "mm",
                    },
                    "daily": {
                        "time": [(start + timedelta(days=n)).isoformat() for n in range(count)],
                        "temperature_2m_min": [5] * count,
                        "temperature_2m_max": [25] * count,
                        "precipitation_sum": [2] * count,
                    },
                },
            )
        if service == "gemini" and request.url.path == "/v1beta/auth_tokens":
            return httpx.Response(200, json={"name": "auth_tokens/fixture-only-not-a-live-token"})
        if service == "gemini" and request.url.path.endswith(":streamGenerateContent"):
            # Preserve the raw thought/signature part; it is not visible first text.
            thought = {
                "candidates": [
                    {
                        "content": {
                            "parts": [
                                {
                                    "text": "Synthetic thought",
                                    "thought": True,
                                    "thoughtSignature": "fixture-only",
                                }
                            ]
                        }
                    }
                ]
            }
            body = "".join("data: " + json.dumps(event) + "\n\n" for event in (thought, payload))
            return httpx.Response(200, content=body, headers={"content-type": "text/event-stream"})
        if service == "twilio" and request.url.path.endswith("/VerificationCheck"):
            payload = {**payload, "status": "approved", "valid": True}
        if service == "turnstile":
            # Echo the caller's requested action so both sign-up and login
            # verify against a matching fixture instead of a fixed value.
            requested = json.loads(request.content or b"{}").get("action", payload["action"])
            payload = {**payload, "action": requested}
        return httpx.Response(200, json=payload)
