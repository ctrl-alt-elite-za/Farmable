"""Same-origin Turnstile page for native authentication; never contains secrets."""

import json
import secrets
from pathlib import Path
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, HTMLResponse

from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.record_access import ApiError

router = APIRouter(include_in_schema=False)
_SCRIPT = Path(__file__).parent / "static" / "turnstile.js"


@router.get("/auth/turnstile.js")
def challenge_script() -> FileResponse:
    return FileResponse(
        _SCRIPT,
        media_type="text/javascript",
        headers={"Cache-Control": "no-store", "X-Content-Type-Options": "nosniff"},
    )


@router.get("/auth/turnstile")
def challenge_page(
    request: Request,
    action: Literal["sign_up", "login"],
    state: UUID,
) -> HTMLResponse:
    settings: ServiceSettings = request.app.state.services.turnstile.settings
    simulation = settings.environment == "ci" and settings.integrations_mode == "fake"
    if not simulation and (
        settings.integrations_mode != "live"
        or not settings.turnstile_site_key
        or not settings.turnstile_secret
        or not settings.turnstile_hostname
        or request.url.hostname != settings.turnstile_hostname
    ):
        raise ApiError(503, "provider_unavailable")
    config = json.dumps(
        {
            "action": action,
            "state": str(state),
            "sitekey": None if simulation else settings.turnstile_site_key,
            "simulation": simulation,
        }
    ).replace("<", "\\u003c")
    nonce = secrets.token_urlsafe(24)
    provider_script = (
        ""
        if simulation
        else (
            '<script src="https://challenges.cloudflare.com/turnstile/v0/api.js'
            '?onload=onFarmableChallengeReady&amp;render=explicit" defer></script>'
        )
    )
    return HTMLResponse(
        f'<!doctype html><html lang="en"><head><meta charset="utf-8">'
        '<meta name="viewport" content="width=device-width, initial-scale=1">'
        "<title>Verify to continue</title></head><body>"
        '<div id="challenge"></div>'
        f'<script id="challenge-config" type="application/json" nonce="{nonce}">{config}</script>'
        f'<script nonce="{nonce}" src="/auth/turnstile.js"></script>'
        f"{provider_script}</body></html>",
        headers={
            "Cache-Control": "no-store",
            "Referrer-Policy": "no-referrer",
            "X-Content-Type-Options": "nosniff",
            "Content-Security-Policy": (
                "default-src 'none'; "
                f"script-src 'nonce-{nonce}' https://challenges.cloudflare.com; "
                "frame-src https://challenges.cloudflare.com; "
                "connect-src https://challenges.cloudflare.com; "
                "style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'; "
                "frame-ancestors 'none'"
            ),
        },
    )
