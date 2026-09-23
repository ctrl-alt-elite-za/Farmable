"""Opt-in staging client: one authenticated mint, one Gemini Live audio turn.

No microphone, persisted audio, key, automatic retry, or application mutation.
The caller supplies an existing verified Farmable session, never a Google key.
"""

import argparse
import asyncio
import base64
import json
import logging
import os
import re
from dataclasses import dataclass, field
from datetime import UTC, datetime
from typing import Any

import httpx
from websockets.asyncio.client import connect

LIVE_URL = (
    "wss://generativelanguage.googleapis.com/ws/"
    "google.ai.generativelanguage.v1beta.GenerativeService.BidiGenerateContentConstrained"
)
HTTP_LIMIT = 32 * 1024
MESSAGE_LIMIT = 512 * 1024
TOTAL_LIMIT = 4 * 1024 * 1024
MESSAGE_COUNT = 256
TOTAL_SECONDS = 60
SETUP_SECONDS = 10
TURN_SECONDS = 30


class SmokeFailure(Exception):
    """Only fixed, local failure codes may reach the CLI."""


@dataclass(frozen=True)
class Config:
    api_url: str
    expected_sha: str
    access_token: str = field(repr=False)

    def __post_init__(self) -> None:
        if (
            re.fullmatch(r"https://[a-z0-9-]+(?:\.[a-z0-9-]+)*\.run\.app", self.api_url) is None
            or re.fullmatch(r"[0-9a-f]{40}", self.expected_sha) is None
            or re.fullmatch(r"[A-Za-z0-9_-]{43}", self.access_token) is None
        ):
            raise SmokeFailure("invalid_configuration")


@dataclass(frozen=True)
class Credential:
    model: str
    connect_by: datetime
    token: str = field(repr=False)


class NoRedirectConnect(connect):
    # websockets 15 follows handshake redirects by default, including headers.
    # Fail instead of allowing the ephemeral credential to leave Google's host.
    def process_redirect(self, exc: Exception) -> Exception:
        return exc


async def read_http(client: httpx.AsyncClient, method: str, path: str, **kwargs) -> dict[str, Any]:
    async with client.stream(method, path, **kwargs) as response:
        if response.status_code != 200:
            codes = {
                401: "authentication_failed",
                403: "access_denied",
                429: "rate_limited",
                503: "service_unavailable",
            }
            raise SmokeFailure(codes.get(response.status_code, "http_failed"))
        if response.headers.get("content-encoding", "identity") != "identity":
            raise SmokeFailure("encoded_response_refused")
        if path == "/voice/live-session" and (
            response.headers.get("cache-control") != "no-store"
            or response.headers.get("pragma") != "no-cache"
        ):
            raise SmokeFailure("unsafe_credential_cache_policy")
        data = bytearray()
        async for chunk in response.aiter_raw(chunk_size=4096):
            if len(data) + len(chunk) > HTTP_LIMIT:
                raise SmokeFailure("http_response_limit")
            data.extend(chunk)
        document = json.loads(data)
        if not isinstance(document, dict):
            raise SmokeFailure("invalid_response")
        return document


def credential(document: dict[str, Any]) -> Credential:
    token, model = document.get("credential"), document.get("model")
    if (
        document.get("mode") != "live"
        or document.get("api_version") != "v1beta"
        or not isinstance(token, str)
        or re.fullmatch(r"auth_tokens/[!-~]{1,8192}", token) is None
        or not isinstance(model, str)
        or re.fullmatch(r"models/[a-zA-Z0-9._-]{1,128}", model) is None
    ):
        raise SmokeFailure("invalid_live_credential")
    try:
        expiry = datetime.fromisoformat(document["expires_at"])
        connect_by = datetime.fromisoformat(document["new_session_expires_at"])
        now = datetime.now(UTC)
        # Reject naive dates, stale credentials and policies longer than the API contract.
        if not (5 < (connect_by - now).total_seconds() <= 60):
            raise ValueError
        if not (connect_by < expiry and 0 < (expiry - now).total_seconds() <= 600):
            raise ValueError
    except (KeyError, TypeError, ValueError):
        raise SmokeFailure("invalid_credential_deadline") from None
    return Credential(model, connect_by, token)


async def audio_turn(ws, grant: Credential) -> None:
    total = 0
    count = 0

    async def receive() -> dict:
        nonlocal total, count
        raw = await ws.recv()
        size = len(raw.encode("utf-8")) if isinstance(raw, str) else len(raw)
        total += size
        count += 1
        if size > MESSAGE_LIMIT or total > TOTAL_LIMIT or count > MESSAGE_COUNT:
            raise SmokeFailure("websocket_response_limit")
        message = json.loads(raw)
        if not isinstance(message, dict) or any(
            key in message for key in ("error", "toolCall", "toolCallCancellation", "goAway")
        ):
            raise SmokeFailure("unexpected_live_message")
        return message

    async with asyncio.timeout(SETUP_SECONDS):
        if datetime.now(UTC) >= grant.connect_by:
            raise SmokeFailure("credential_connection_expired")
        await ws.send(
            json.dumps(
                {
                    "setup": {
                        "model": grant.model,
                        "generationConfig": {"responseModalities": ["AUDIO"]},
                        "sessionResumption": {},
                    }
                }
            )
        )
        setup = await receive()
        if not isinstance(setup.get("setupComplete"), dict):
            raise SmokeFailure("setup_not_confirmed")

    audio_bytes = 0
    async with asyncio.timeout(TURN_SECONDS):
        await ws.send(
            json.dumps(
                {
                    "clientContent": {
                        "turns": [
                            {"role": "user", "parts": [{"text": "Say: Farmable connection test."}]}
                        ],
                        "turnComplete": True,
                    }
                }
            )
        )
        while True:
            message = await receive()
            content = message.get("serverContent")
            if content is None:
                if set(message) - {"usageMetadata", "sessionResumptionUpdate"}:
                    raise SmokeFailure("unexpected_live_message")
                continue
            if not isinstance(content, dict) or content.get("interrupted"):
                raise SmokeFailure("audio_turn_interrupted")
            for part in content.get("modelTurn", {}).get("parts", []):
                inline = part.get("inlineData")
                if inline is None:
                    continue
                if inline.get("mimeType") != "audio/pcm;rate=24000":
                    raise SmokeFailure("invalid_audio_format")
                pcm = base64.b64decode(inline["data"], validate=True)
                if not pcm or len(pcm) % 2:
                    raise SmokeFailure("invalid_audio_data")
                audio_bytes += len(pcm)
            if content.get("turnComplete") is True:
                if audio_bytes == 0:
                    raise SmokeFailure("no_audio_received")
                return


async def smoke(config: Config, *, transport=None, connector=NoRedirectConnect) -> None:
    # A dedicated disabled logger also prevents debug handlers from exposing WS headers/frames.
    wire_logger = logging.Logger("farmable-live-smoke-wire")
    wire_logger.disabled = True
    async with asyncio.timeout(TOTAL_SECONDS):
        async with httpx.AsyncClient(
            base_url=config.api_url,
            transport=transport,
            follow_redirects=False,
            trust_env=False,
            timeout=10,
            headers={"Accept-Encoding": "identity"},
        ) as client:
            ready = await read_http(client, "GET", "/health/ready")
            if (
                ready.get("sha") != config.expected_sha
                or ready.get("database") != "ok"
                or ready.get("worker") != "ok"
            ):
                raise SmokeFailure("wrong_or_unhealthy_revision")
            grant = credential(
                await read_http(
                    client,
                    "POST",
                    "/voice/live-session",
                    headers={"Authorization": "Bearer " + config.access_token},
                )
            )
        async with connector(
            LIVE_URL,
            additional_headers={"Authorization": "Token " + grant.token},
            proxy=None,
            compression=None,
            open_timeout=10,
            close_timeout=2,
            max_size=MESSAGE_LIMIT,
            max_queue=4,
            logger=wire_logger,
        ) as ws:
            await audio_turn(ws, grant)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--allow-paid", action="store_true")
    args = parser.parse_args(argv)
    # CLI output is exclusively fixed codes; never print exceptions, URLs or payloads.
    for name in ("httpx", "httpcore", "websockets"):
        logging.getLogger(name).disabled = True
        logging.getLogger(name).setLevel(logging.CRITICAL)
    if (
        not args.live
        or not args.allow_paid
        or os.getenv("ENVIRONMENT") != "staging"
        or os.getenv("INTEGRATIONS_MODE") != "live"
        or any(
            os.getenv(name, "").lower() not in {"", "0", "false"}
            for name in ("CI", "GITHUB_ACTIONS")
        )
    ):
        print("FAIL gemini_live live_staging_authorization_required")
        return 1
    try:
        config = Config(
            os.getenv("SMOKE_API_URL", ""),
            os.getenv("SMOKE_EXPECTED_SHA", ""),
            os.getenv("SMOKE_ACCESS_TOKEN", ""),
        )
        asyncio.run(smoke(config))
    except SmokeFailure as error:
        print("FAIL gemini_live " + str(error))
        return 1
    except (TimeoutError, httpx.TimeoutException):
        print("FAIL gemini_live timeout")
        return 1
    except KeyboardInterrupt:
        print("FAIL gemini_live interrupted")
        return 130
    except Exception:
        print("FAIL gemini_live connection_or_response_failed")
        return 1
    print("PASS gemini_live audio_turn_completed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
