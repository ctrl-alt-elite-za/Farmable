"""Authenticated farm-tool capabilities; audio remains on the existing direct Live path."""

from contextlib import suppress
from uuid import UUID

import anyio
from fastapi import APIRouter, Depends, Request, Response

from farmable_backend.assistant.api import runtime
from farmable_backend.assistant.live import (
    LiveConsentGrant,
    LiveConsentView,
    LiveIssued,
    LiveStart,
    LiveState,
    LiveStore,
    LiveToolCall,
    LiveToolResult,
    setup_for,
)
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import bearer, token
from farmable_backend.schemas import ErrorResponse

router = APIRouter(
    prefix="/assistant/conversations/{conversation_id}",
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 403, 404, 409, 422, 429, 503)},
)


def context(request, response):
    if request.query_params:
        raise ApiError(422, "validation_error")
    value = runtime(request)
    adapter = request.app.state.services.gemini_live
    response.headers["Cache-Control"] = "no-store"
    response.headers["Pragma"] = "no-cache"
    return value, adapter, LiveStore(value.store, adapter)


@router.get("/live-consent", response_model=LiveConsentView, operation_id="getAssistantLiveConsent")
async def consent(request: Request, response: Response, conversation_id: UUID):
    value, _, store = context(request, response)
    return await value.worker.call(store.consent, token(request), conversation_id)


@router.put(
    "/live-consent", response_model=LiveConsentView, operation_id="grantAssistantLiveConsent"
)
async def grant(
    request: Request, response: Response, conversation_id: UUID, payload: LiveConsentGrant
):
    value, _, store = context(request, response)
    return await value.worker.call(store.consent, token(request), conversation_id, payload)


@router.delete(
    "/live-consent", response_model=LiveConsentView, operation_id="withdrawAssistantLiveConsent"
)
async def withdraw(request: Request, response: Response, conversation_id: UUID):
    value, _, store = context(request, response)
    return await value.worker.call(store.consent, token(request), conversation_id, None, True)


@router.post("/live-sessions", response_model=LiveIssued, operation_id="createAssistantLiveSession")
async def issue(request: Request, response: Response, conversation_id: UUID, payload: LiveStart):
    value, adapter, store = context(request, response)
    auth = token(request)
    model = await value.worker.call(store.admit, auth, conversation_id, payload.id)
    try:
        setup = setup_for(model)
        result = await adapter.issue(setup=setup)
        if not result.ok:
            code = {
                "disabled": "voice_disabled",
                "capacity": "capacity_unavailable",
                "timeout": "voice_timeout",
            }.get(result.error or "", "voice_unavailable")
            raise ApiError(503, code, 5)
        # Validate before publishing. Withdrawal/regrant, deletion, interruption
        # or a changed model during provider I/O must never release a credential.
        data = result.data or {}
        issued = LiveIssued.model_validate(
            {
                **data,
                "id": payload.id,
                "lease_expires_at": data.get("expires_at"),
                "setup": setup,
            }
        )
        issued.lease_expires_at = await value.worker.call(
            store.activate,
            auth,
            conversation_id,
            payload.id,
            issued.model,
        )
        return issued
    except BaseException:
        with anyio.move_on_after(5, shield=True):
            with suppress(Exception):
                await value.worker.call(store.fail, payload.id)
        raise


@router.get(
    "/live-sessions/{session_id}", response_model=LiveState, operation_id="getAssistantLiveSession"
)
async def state(request: Request, response: Response, conversation_id: UUID, session_id: UUID):
    value, _, store = context(request, response)
    return await value.worker.call(store.state, token(request), conversation_id, session_id)


@router.post(
    "/live-sessions/{session_id}/interrupt",
    response_model=LiveState,
    operation_id="interruptAssistantLiveSession",
)
async def interrupt(request: Request, response: Response, conversation_id: UUID, session_id: UUID):
    value, _, store = context(request, response)
    return await value.worker.call(store.state, token(request), conversation_id, session_id, True)


@router.post(
    "/live-sessions/{session_id}/tools",
    response_model=LiveToolResult,
    operation_id="executeAssistantLiveTool",
)
async def tool(
    request: Request,
    response: Response,
    conversation_id: UUID,
    session_id: UUID,
    payload: LiveToolCall,
):
    value, _, store = context(request, response)
    return await value.worker.call(
        store.tool, token(request), conversation_id, session_id, payload, value.mode
    )
