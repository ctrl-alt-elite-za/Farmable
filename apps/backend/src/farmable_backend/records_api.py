"""Authenticated record routes with bounded synchronous admission."""

import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor
from contextvars import copy_context
from functools import partial
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Query, Request, Response
from fastapi.security import HTTPBearer
from sqlalchemy.exc import OperationalError
from sqlalchemy.exc import TimeoutError as DatabaseTimeout
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from farmable_backend.farm_records import RecordConflictError, RecordNotFoundError
from farmable_backend.middleware import error_response
from farmable_backend.record_access import ApiError
from farmable_backend.records_schemas import (
    FarmView,
    ObservationAck,
    ObservationCreate,
    ObservationView,
    Page,
    SectionView,
    SignedForm,
    UploadCreate,
    UploadRetry,
    UploadView,
)
from farmable_backend.records_service import RecordsService
from farmable_backend.schemas import ErrorResponse
from farmable_backend.uploads import UploadError


class RecordRuntime:
    def __init__(self, service: RecordsService, storage_factory):
        self.service = service
        self.storage_factory = storage_factory
        self.storage = None
        self.storage_lock = threading.Lock()
        self.slots = threading.BoundedSemaphore(8)
        self.executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="farmable-records")

    async def call(self, function, *args, **kwargs):
        if not self.slots.acquire(blocking=False):
            raise ApiError(503, "capacity_unavailable", 1)
        try:
            future = self.executor.submit(partial(copy_context().run, function, *args, **kwargs))
        except BaseException:
            self.slots.release()
            raise
        # Cancellation does not release a slot while its thread is still running.
        future.add_done_callback(lambda _: self.slots.release())
        try:
            return await asyncio.wrap_future(future)
        except RecordNotFoundError:
            raise ApiError(404, "not_found") from None
        except RecordConflictError:
            raise ApiError(409, "mutation_conflict") from None
        except (OperationalError, DatabaseTimeout, UploadError):
            raise ApiError(503, "dependency_unavailable", 5) from None

    def reserve(self, authorization, farm_id, payload):
        view, upload, attempt = self.service.reserve(authorization, farm_id, payload)
        if view.state != "awaiting_upload":
            return view
        with self.storage_lock:
            if self.storage is None:
                self.storage = self.storage_factory()
            storage = self.storage
        if storage is None:
            raise ApiError(503, "photo_storage_disabled")
        form = storage.prepare(upload, attempt)
        self.service.upload(authorization, farm_id, upload.id, expected_attempt=attempt.id)
        view.form = SignedForm(url=form.url, fields=form.fields, expires_at=attempt.form_expires_at)
        return view

    def close(self):
        self.executor.shutdown(wait=True, cancel_futures=True)
        if self.storage is not None:
            self.storage.close()


class RecordBodyLimit:
    """Bound JSON before FastAPI buffers it, even for chunked requests."""

    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if (
            scope["type"] != "http"
            or scope.get("method") != "POST"
            or not scope.get("path", "").startswith("/farms/")
        ):
            return await self.app(scope, receive, send)
        chunks = []
        length = 0
        while True:
            message = await receive()
            if message["type"] == "http.disconnect":
                return
            chunk = message.get("body", b"")
            length += len(chunk)
            if length > 65_536:
                return await error_response(413, "body_too_large", "Request too large")(
                    scope, receive, send
                )
            chunks.append(chunk)
            if not message.get("more_body", False):
                break
        delivered = False

        async def bounded_receive() -> Message:
            nonlocal delivered
            if delivered:
                return await receive()
            delivered = True
            return {"type": "http.request", "body": b"".join(chunks), "more_body": False}

        await self.app(scope, bounded_receive, send)


bearer = HTTPBearer(auto_error=False, scheme_name="SessionBearer")
router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 409, 413, 503)},
)
Limit = Annotated[int, Query(ge=1, le=100)]


def runtime(request: Request) -> RecordRuntime:
    value = getattr(request.app.state, "records", None)
    if value is None:
        raise ApiError(503, "records_unavailable")
    return value


def token(request: Request) -> str | None:
    values = request.headers.getlist("authorization")
    if len(values) != 1:
        raise ApiError(401, "invalid_session")
    return values[0]


@router.get("/farms", response_model=Page[FarmView], operation_id="listFarms")
async def farms(request: Request, cursor: UUID | None = None, limit: Limit = 50):
    worker = runtime(request)
    return await worker.call(
        worker.service.read, token(request), "farms", None, None, None, cursor, limit
    )


@router.get(
    "/farms/{farm_id}/sections", response_model=Page[SectionView], operation_id="listSections"
)
async def sections(request: Request, farm_id: UUID, cursor: UUID | None = None, limit: Limit = 50):
    worker = runtime(request)
    return await worker.call(
        worker.service.read, token(request), "sections", farm_id, None, None, cursor, limit
    )


@router.get(
    "/farms/{farm_id}/observations",
    response_model=Page[ObservationView],
    operation_id="listObservations",
)
async def observations(
    request: Request,
    farm_id: UUID,
    section_id: UUID | None = None,
    cursor: UUID | None = None,
    limit: Limit = 50,
):
    worker = runtime(request)
    return await worker.call(
        worker.service.read,
        token(request),
        "observations",
        farm_id,
        section_id,
        None,
        cursor,
        limit,
    )


@router.get(
    "/farms/{farm_id}/observations/{observation_id}",
    response_model=ObservationView,
    operation_id="getObservation",
)
async def observation(request: Request, farm_id: UUID, observation_id: UUID):
    worker = runtime(request)
    return await worker.call(
        worker.service.read, token(request), "observations", farm_id, None, observation_id, None, 1
    )


@router.post(
    "/farms/{farm_id}/observations", response_model=ObservationAck, operation_id="createObservation"
)
async def create_observation(request: Request, farm_id: UUID, payload: ObservationCreate):
    worker = runtime(request)
    return await worker.call(worker.service.observe, token(request), farm_id, payload)


@router.post(
    "/farms/{farm_id}/photo-uploads",
    response_model=UploadView,
    operation_id="reservePhotoUpload",
    response_model_exclude_none=True,
)
async def reserve_photo(request: Request, response: Response, farm_id: UUID, payload: UploadCreate):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.reserve, token(request), farm_id, payload)


@router.get(
    "/farms/{farm_id}/photo-uploads/{upload_id}",
    response_model=UploadView,
    operation_id="getPhotoUpload",
    response_model_exclude_none=True,
)
async def get_photo(request: Request, response: Response, farm_id: UUID, upload_id: UUID):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.service.upload, token(request), farm_id, upload_id)


@router.post(
    "/farms/{farm_id}/photo-uploads/{upload_id}/retry",
    response_model=UploadView,
    operation_id="retryPhotoUpload",
    response_model_exclude_none=True,
)
async def retry_photo(
    request: Request, response: Response, farm_id: UUID, upload_id: UUID, payload: UploadRetry
):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(
        worker.service.retry_upload, token(request), farm_id, upload_id, payload.failed_attempt_id
    )


@router.post(
    "/farms/{farm_id}/photo-uploads/{upload_id}/complete",
    response_model=UploadView,
    operation_id="completePhotoUpload",
    response_model_exclude_none=True,
    responses={202: {"model": UploadView}},
)
async def complete_photo(request: Request, response: Response, farm_id: UUID, upload_id: UUID):
    if (await request.body()).strip() not in (b"", b"{}"):
        raise ApiError(422, "validation_error")
    worker = runtime(request)
    result = await worker.call(
        worker.service.upload, token(request), farm_id, upload_id, complete=True
    )
    response.headers["Cache-Control"] = "no-store"
    response.status_code = 200 if result.state == "ready" else 202
    return result
