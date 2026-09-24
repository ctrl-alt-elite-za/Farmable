"""Authenticated record routes with bounded synchronous admission."""

import asyncio
import threading
import time
from concurrent.futures import ThreadPoolExecutor
from contextvars import copy_context
from functools import partial
from typing import Annotated, Any
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
    ChangePage,
    FarmView,
    FinancialCreate,
    FinancialUpdate,
    FinancialView,
    MediaCreate,
    MediaUpdate,
    MediaView,
    ObservationAck,
    ObservationCreate,
    ObservationUpdate,
    ObservationView,
    Page,
    PlanCreate,
    PlantingCreate,
    PlantingUpdate,
    PlantingView,
    PlanUpdate,
    PlanView,
    RecordAck,
    RecordDelete,
    SectionCreate,
    SectionDetail,
    SectionUpdate,
    SectionView,
    SignedForm,
    TaskCreate,
    TaskUpdate,
    TaskView,
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
        self.storage_initialized = False
        self.storage_initializing = False
        self.storage_retry_at = 0.0
        self.slots = threading.BoundedSemaphore(8)
        self.executor = ThreadPoolExecutor(max_workers=8, thread_name_prefix="farmable-records")
        self.photo_slots = threading.BoundedSemaphore(2)
        self.photo_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="farmable-forms")

    async def call(self, function, *args, **kwargs):
        return await self._call(self.executor, self.slots, function, *args, **kwargs)

    async def call_photo(self, function, *args, **kwargs):
        return await self._call(self.photo_executor, self.photo_slots, function, *args, **kwargs)

    async def _call(self, executor, slots, function, *args, **kwargs):
        if not slots.acquire(blocking=False):
            raise ApiError(503, "capacity_unavailable", 1)
        try:
            future = executor.submit(partial(copy_context().run, function, *args, **kwargs))
        except BaseException:
            slots.release()
            raise
        # Cancellation does not release a slot while its thread is still running.
        future.add_done_callback(lambda _: slots.release())
        try:
            return await asyncio.wrap_future(future)
        except RecordNotFoundError:
            raise ApiError(404, "not_found") from None
        except RecordConflictError:
            raise ApiError(409, "mutation_conflict") from None
        except (OperationalError, DatabaseTimeout, UploadError):
            raise ApiError(503, "dependency_unavailable", 5) from None

    def get_storage(self):
        # Never hold this lock across credential discovery/network I/O. Other
        # reservations fail promptly while one bootstrap is pending or cooling down.
        with self.storage_lock:
            if self.storage_initialized:
                if self.storage is None:
                    raise ApiError(503, "photo_storage_disabled")
                return self.storage
            if self.storage_initializing:
                raise ApiError(503, "dependency_unavailable", 1)
            if time.monotonic() < self.storage_retry_at:
                raise ApiError(503, "dependency_unavailable", 30)
            self.storage_initializing = True
        try:
            storage = self.storage_factory()
        except Exception:
            with self.storage_lock:
                self.storage_retry_at = time.monotonic() + 30
            raise ApiError(503, "dependency_unavailable", 30) from None
        else:
            with self.storage_lock:
                self.storage = storage
                self.storage_initialized = True
        finally:
            with self.storage_lock:
                self.storage_initializing = False
        if storage is None:
            raise ApiError(503, "photo_storage_disabled")
        return storage

    def reserve(self, authorization, farm_id, payload):
        view, upload, attempt = self.service.reserve(authorization, farm_id, payload)
        if view.state != "awaiting_upload":
            return view
        storage = self.get_storage()
        form = storage.prepare(upload, attempt)
        self.service.upload(authorization, farm_id, upload.id, expected_attempt=attempt.id)
        view.form = SignedForm(url=form.url, fields=form.fields, expires_at=attempt.form_expires_at)
        return view

    def close(self):
        self.executor.shutdown(wait=True, cancel_futures=True)
        self.photo_executor.shutdown(wait=True, cancel_futures=True)
        if self.storage is not None:
            self.storage.close()


class RecordBodyLimit:
    """Bound JSON before FastAPI buffers it, even for chunked requests."""

    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send):
        if (
            scope["type"] != "http"
            or scope.get("method") not in ("POST", "PUT")
            or not scope.get("path", "").startswith(("/farms/", "/assistant/"))
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
    "/farms/{farm_id}/observations/{record_id}",
    response_model=ObservationView,
    operation_id="getObservation",
)
async def observation(request: Request, farm_id: UUID, record_id: UUID):
    worker = runtime(request)
    return await worker.call(
        worker.service.read, token(request), "observations", farm_id, None, record_id, None, 1
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
    return await worker.call_photo(worker.reserve, token(request), farm_id, payload)


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


Since = Annotated[int, Query(ge=0)]


@router.get("/farms/{farm_id}/changes", response_model=ChangePage, operation_id="listChanges")
async def changes(request: Request, farm_id: UUID, since: Since = 0, limit: Limit = 50):
    worker = runtime(request)
    return await worker.call(worker.service.changes, token(request), farm_id, since, limit)


@router.get(
    "/farms/{farm_id}/sections/{record_id}",
    response_model=SectionDetail,
    operation_id="getSection",
)
async def section_detail(request: Request, farm_id: UUID, record_id: UUID):
    worker = runtime(request)
    return await worker.call(worker.service.section_detail, token(request), farm_id, record_id)


def register_resource(
    resource: str,
    singular: str,
    plural: str,
    create_model: Any,
    update_model: Any,
    view_model: Any,
    operations: tuple[str, ...],
) -> None:
    """Register the uniform owner-scoped routes for one record resource."""
    collection = "/farms/{farm_id}/" + resource
    item = collection + "/{record_id}"

    if "list" in operations:

        async def list_records(
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
                resource,
                farm_id,
                section_id,
                None,
                cursor,
                limit,
            )

        router.add_api_route(
            collection,
            list_records,
            methods=["GET"],
            response_model=Page[view_model],
            operation_id=f"list{plural}",
        )

    if "get" in operations:

        async def get_record(request: Request, farm_id: UUID, record_id: UUID):
            worker = runtime(request)
            return await worker.call(
                worker.service.read, token(request), resource, farm_id, None, record_id, None, 1
            )

        router.add_api_route(
            item,
            get_record,
            methods=["GET"],
            response_model=view_model,
            operation_id=f"get{singular}",
        )

    if "create" in operations:

        async def create_record(
            request: Request,
            farm_id: UUID,
            payload: create_model,
        ):
            worker = runtime(request)
            return await worker.call(
                worker.service.mutate, token(request), farm_id, resource, "create", None, payload
            )

        router.add_api_route(
            collection,
            create_record,
            methods=["POST"],
            response_model=RecordAck[view_model],
            operation_id=f"create{singular}",
        )

    if "update" in operations:

        async def update_record(
            request: Request,
            farm_id: UUID,
            record_id: UUID,
            payload: update_model,
        ):
            worker = runtime(request)
            return await worker.call(
                worker.service.mutate,
                token(request),
                farm_id,
                resource,
                "update",
                record_id,
                payload,
            )

        router.add_api_route(
            item,
            update_record,
            methods=["PUT"],
            response_model=RecordAck[view_model],
            operation_id=f"update{singular}",
        )

    if "delete" in operations:

        async def delete_record(
            request: Request,
            farm_id: UUID,
            record_id: UUID,
            payload: RecordDelete,
        ):
            worker = runtime(request)
            return await worker.call(
                worker.service.mutate,
                token(request),
                farm_id,
                resource,
                "delete",
                record_id,
                payload,
            )

        router.add_api_route(
            item + "/delete",
            delete_record,
            methods=["POST"],
            response_model=RecordAck[view_model],
            operation_id=f"delete{singular}",
        )


register_resource(
    "sections",
    "Section",
    "Sections",
    SectionCreate,
    SectionUpdate,
    SectionView,
    ("create", "update", "delete"),
)
register_resource(
    "plantings",
    "Planting",
    "Plantings",
    PlantingCreate,
    PlantingUpdate,
    PlantingView,
    ("list", "get", "create", "update", "delete"),
)
register_resource(
    "observations",
    "Observation",
    "Observations",
    None,
    ObservationUpdate,
    ObservationView,
    ("update", "delete"),
)
register_resource(
    "tasks",
    "Task",
    "Tasks",
    TaskCreate,
    TaskUpdate,
    TaskView,
    ("list", "get", "create", "update", "delete"),
)
register_resource(
    "financials",
    "Financial",
    "Financials",
    FinancialCreate,
    FinancialUpdate,
    FinancialView,
    ("list", "get", "create", "update", "delete"),
)
register_resource(
    "plans",
    "Plan",
    "Plans",
    PlanCreate,
    PlanUpdate,
    PlanView,
    ("list", "get", "create", "update", "delete"),
)
register_resource(
    "media",
    "MediaItem",
    "MediaItems",
    MediaCreate,
    MediaUpdate,
    MediaView,
    ("list", "get", "create", "update", "delete"),
)
