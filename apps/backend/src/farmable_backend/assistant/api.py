import json
from contextlib import suppress
from uuid import UUID

import anyio
from fastapi import APIRouter, Depends, Request, Response
from fastapi.responses import StreamingResponse

from farmable_backend.assistant.privacy import ConsentGrant, ConsentView
from farmable_backend.assistant.schemas import (
    ConversationCreate,
    ConversationView,
    History,
    StreamEvent,
    TurnCreate,
    TurnView,
)
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import bearer, token
from farmable_backend.schemas import ErrorResponse

router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 403, 404, 409, 503)},
)
SEND_SECONDS = 5


def runtime(request):
    value = getattr(request.app.state, "assistant", None)
    if value is None:
        raise ApiError(503, "assistant_disabled")
    return value


class AssistantResponse(StreamingResponse):
    """Release admission even if disconnect happens before the generator starts."""

    def __init__(self, content, cleanup, **kwargs):
        super().__init__(content, **kwargs)
        self.cleanup = cleanup

    async def __call__(self, scope, receive, send):
        async def bounded_send(message):
            with anyio.fail_after(SEND_SECONDS):
                await send(message)

        try:
            await super().__call__(scope, receive, bounded_send)
        finally:
            # ASGI cancellation scopes otherwise cancel the cleanup DB call too.
            with anyio.move_on_after(5, shield=True):
                with suppress(Exception):
                    await self.body_iterator.aclose()
                await self.cleanup()


@router.post(
    "/assistant/conversations",
    response_model=ConversationView,
    operation_id="createAssistantConversation",
)
async def create(request: Request, response: Response, payload: ConversationCreate):
    value = runtime(request)
    response.headers["Cache-Control"] = "no-store"
    return await value.worker.call(value.store.create, token(request), payload)


@router.get(
    "/assistant/conversations/{conversation_id}/consent",
    response_model=ConsentView,
    operation_id="getAssistantConsent",
)
async def consent(request: Request, response: Response, conversation_id: UUID):
    value = runtime(request)
    response.headers["Cache-Control"] = "no-store"
    return await value.worker.call(value.store.consent, token(request), conversation_id)


@router.put(
    "/assistant/conversations/{conversation_id}/consent",
    response_model=ConsentView,
    operation_id="grantAssistantConsent",
)
async def grant_consent(
    request: Request, response: Response, conversation_id: UUID, payload: ConsentGrant
):
    value = runtime(request)
    response.headers["Cache-Control"] = "no-store"
    return await value.worker.call(value.store.consent, token(request), conversation_id, payload)


@router.delete(
    "/assistant/conversations/{conversation_id}/consent",
    response_model=ConsentView,
    operation_id="withdrawAssistantConsent",
)
async def withdraw_consent(request: Request, response: Response, conversation_id: UUID):
    value = runtime(request)
    response.headers["Cache-Control"] = "no-store"
    return await value.worker.call(
        value.store.consent, token(request), conversation_id, withdraw=True
    )


@router.get(
    "/assistant/conversations/{conversation_id}/turns",
    response_model=History,
    operation_id="getAssistantHistory",
)
async def history(
    request: Request, response: Response, conversation_id: UUID, before: UUID | None = None
):
    value = runtime(request)
    response.headers["Cache-Control"] = "no-store"
    return await value.worker.call(value.store.history, token(request), conversation_id, before)


@router.get(
    "/assistant/conversations/{conversation_id}/turns/{turn_id}",
    response_model=TurnView,
    operation_id="getAssistantTurn",
)
async def get(request: Request, response: Response, conversation_id: UUID, turn_id: UUID):
    value = runtime(request)
    response.headers["Cache-Control"] = "no-store"
    return await value.worker.call(value.store.get, token(request), conversation_id, turn_id)


@router.post(
    "/assistant/conversations/{conversation_id}/turns/{turn_id}/interrupt",
    response_model=TurnView,
    operation_id="interruptAssistantTurn",
)
async def interrupt(request: Request, response: Response, conversation_id: UUID, turn_id: UUID):
    value = runtime(request)
    response.headers["Cache-Control"] = "no-store"
    return await value.worker.call(value.store.interrupt, token(request), conversation_id, turn_id)


@router.post(
    "/assistant/conversations/{conversation_id}/turns",
    operation_id="streamAssistantTurn",
    response_class=StreamingResponse,
    responses={
        200: {
            "content": {
                "text/event-stream": {
                    "schema": {
                        "type": "string",
                        "description": "SSE events; each data line is StreamEvent JSON",
                    }
                }
            },
            "description": "accepted, text/tool events, then done/error/interrupted",
        }
    },
)
async def stream(request: Request, conversation_id: UUID, payload: TurnCreate):
    value = runtime(request)
    auth = token(request)
    if len(value.active) >= 4:
        raise ApiError(503, "assistant_capacity", 1)
    # No await between capacity check and reservation of the local slot.
    # A slot belongs to this HTTP request, not a caller-chosen UUID. A duplicate
    # request must neither expose another owner's active ID nor release its slot.
    slot = object()
    value.active.add(slot)
    try:
        turn, fresh = await value.worker.call(value.store.admit, auth, conversation_id, payload)
    except BaseException:
        value.active.discard(slot)
        raise
    if not fresh:
        value.active.discard(slot)

    async def body():
        try:
            if not fresh:
                event = StreamEvent(
                    type="accepted",
                    turn_id=turn.id,
                    data={"replayed": True, "turn": turn.model_dump(mode="json")},
                )
                yield "event: accepted\ndata: " + event.model_dump_json() + "\n\n"
                kind = (
                    "done"
                    if turn.status == "completed"
                    else "interrupted"
                    if turn.status == "interrupted"
                    else "error"
                )
                data = {
                    "code": "turn_in_progress" if turn.status == "running" else turn.error,
                    "status": turn.status,
                }
                event = StreamEvent(type=kind, turn_id=turn.id, data=data)
                yield f"event: {kind}\ndata: {event.model_dump_json()}\n\n"
                return
            iterator = value.events(auth, conversation_id, turn)
            try:
                async for event in iterator:
                    data = StreamEvent(turn_id=turn.id, **event).model_dump(mode="json")
                    yield f"event: {event['type']}\ndata: {json.dumps(data)}\n\n"
            finally:
                await iterator.aclose()
        finally:
            value.active.discard(slot)

    async def cleanup():
        value.active.discard(slot)
        if fresh:
            with suppress(Exception):
                await value.worker.call(value.store.interrupt, auth, conversation_id, payload.id)

    return AssistantResponse(
        body(),
        cleanup,
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-store",
            "X-Accel-Buffering": "no",
            "X-Content-Type-Options": "nosniff",
        },
    )
