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


PLAN_TRIGGER = "plan"


def _johannesburg_today() -> date:
    from datetime import datetime
    from zoneinfo import ZoneInfo

    return datetime.now(ZoneInfo("Africa/Johannesburg")).date()


def scripted_plan_step(request_body: dict[str, Any]) -> dict[str, Any] | None:
    """The fake model's next step in a planning turn (#23), or None.

    Only when the request offers tools, still allows calling them, and the
    farmer's message asks for a plan: list the sections, preview cabbage on
    the one named (or the first with an area), then answer in words. Every
    other request keeps the fixed fixture reply. Deterministic, no model.
    """
    if not request_body.get("tools"):
        return None
    mode = request_body.get("toolConfig", {}).get("functionCallingConfig", {}).get("mode")
    contents = request_body.get("contents") or []
    if mode != "AUTO" or not contents:
        return None
    asked = next(
        (
            part.get("text", "")
            for content in reversed(contents)
            if content.get("role") == "user"
            for part in content.get("parts", [])
            if isinstance(part, dict) and "text" in part
        ),
        "",
    )
    if PLAN_TRIGGER not in asked.lower():
        return None
    last = contents[-1].get("parts", [])
    answered = {
        part["functionResponse"]["name"]: part["functionResponse"].get("response", {})
        for part in last
        if isinstance(part, dict) and isinstance(part.get("functionResponse"), dict)
    }
    if not answered:
        return {"functionCall": {"name": "list_sections", "args": {"limit": 20}}}
    if "list_sections" in answered:
        sections = [s for s in answered["list_sections"].get("sections", []) if s.get("area_m2")]
        named = [s for s in sections if s.get("name", "").lower() in asked.lower()]
        chosen = (named or sections or [None])[0]
        if chosen is None:
            return {"text": "Which section should I plan? None of them has an area yet."}
        return {
            "functionCall": {
                "name": "preview_planting_plan",
                "args": {
                    "section_id": chosen["id"],
                    "planting_date": (_johannesburg_today() + timedelta(days=7)).isoformat(),
                    "budget_cents": 1_200_000,
                    "money_basis_year": 2025,
                    "crops": [{"crop": "cabbage"}],
                    "planting_cost_percent": 60,
                    "market_commission_bps": 0,
                    "agent_commission_bps": 0,
                },
            }
        }
    return {"text": "Here are the options. Choose one, then review and confirm it in the app."}


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
            try:
                step = scripted_plan_step(json.loads(request.content or b"{}"))
            except (ValueError, AttributeError, KeyError, TypeError):
                step = None
            if step is not None:
                payload = {
                    "candidates": [
                        {"content": {"role": "model", "parts": [step]}, "finishReason": "STOP"}
                    ]
                }
            body = "".join("data: " + json.dumps(event) + "\n\n" for event in (thought, payload))
            return httpx.Response(200, content=body, headers={"content-type": "text/event-stream"})
        if service == "twilio" and request.url.path.endswith("/VerificationCheck"):
            payload = {**payload, "status": "approved", "valid": True}
        return httpx.Response(200, json=payload)
