"""Authenticated credential provisioning; audio streams directly to Gemini."""

import math
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, Request, Response
from pydantic import Field
from sqlalchemy import select

from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.models import User, VoiceSessionRate
from farmable_backend.record_access import ApiError, authenticate, db_now
from farmable_backend.records_api import bearer, runtime, token
from farmable_backend.schemas import ErrorResponse, StrictModel


class LiveSessionResponse(StrictModel):
    credential: str = Field(repr=False, description="Ephemeral secret; keep in memory only.")
    expires_at: datetime
    new_session_expires_at: datetime
    model: str
    api_version: Literal["v1beta"]
    mode: Literal["live", "fake"]


def admit(sessions, authorization: str | None, configured: bool) -> None:
    # Commit admission before the provider call, including failed/abandoned calls.
    # Lock the existing owner row so concurrent first-use inserts are serialized.
    with sessions.begin() as session:
        owner = authenticate(session, authorization)
        if not configured:
            raise ApiError(503, "voice_disabled")
        session.scalar(select(User).where(User.id == owner).with_for_update())
        now = db_now(session).timestamp()
        rate = session.get(VoiceSessionRate, owner)
        hits = [] if rate is None else [hit for hit in rate.hits if hit > now - 3600]
        recent = [hit for hit in hits if hit > now - 60]
        waits = []
        if len(recent) >= 3:
            waits.append(min(recent) + 60 - now)
        if len(hits) >= 20:
            waits.append(min(hits) + 3600 - now)
        if waits:
            raise ApiError(429, "voice_rate_limited", max(1, math.ceil(max(waits))))
        if rate is None:
            rate = VoiceSessionRate(owner_id=owner, hits=[])
            session.add(rate)
        rate.hits = [*hits, now]


router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 503)},
)


@router.post(
    "/voice/live-session", response_model=LiveSessionResponse, operation_id="createLiveSession"
)
async def live_session(request: Request, response: Response):
    authorization = token(request)
    # No caller-controlled model, lifetime, tools, or identity. Reject even chunked
    # bodies without accumulating them in memory. Send this POST with no body.
    if request.query_params:
        raise ApiError(422, "validation_error")
    async for chunk in request.stream():
        if chunk:
            raise ApiError(422, "validation_error")
    worker = runtime(request)
    services: ServiceRegistry = request.app.state.services
    await worker.call(
        admit, worker.service.sessions, authorization, services.gemini_live.configured
    )
    result = await services.gemini_live.issue()
    if not result.ok:
        code = {
            "disabled": "voice_disabled",
            "capacity": "capacity_unavailable",
            "timeout": "voice_timeout",
        }.get(result.error or "", "voice_unavailable")
        raise ApiError(503, code, 5)
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    return LiveSessionResponse.model_validate(result.data)
