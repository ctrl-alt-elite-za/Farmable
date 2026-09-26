"""Authenticated account, privacy and session routes. Owner scope is never a parameter."""

import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor
from contextvars import copy_context
from functools import partial
from typing import Literal
from uuid import UUID

from fastapi import APIRouter, Depends, Request, Response
from fastapi.security import HTTPBearer
from sqlalchemy.exc import OperationalError
from sqlalchemy.exc import TimeoutError as DatabaseTimeout

from farmable_backend.account import EXPORT_BASENAME, AccountService, json_bytes, zip_bytes
from farmable_backend.account_schemas import (
    AccountFarmResponse,
    ConsentResponse,
    ConsentUpdate,
    ContactChangeConfirm,
    DeleteAccountRequest,
    ExportJobCreateResponse,
    ExportJobStatusResponse,
    FarmUpdate,
    ProfileResponse,
    ProfileUpdate,
)
from farmable_backend.auth import Channel
from farmable_backend.idempotency import fingerprint as idempotency_fingerprint
from farmable_backend.middleware import client_address
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import token
from farmable_backend.schemas import ErrorResponse


class AccountRuntime:
    """Bounded off-loop admission for blocking account transactions and Argon2."""

    def __init__(self, service: AccountService):
        self.service = service
        self.slots = threading.BoundedSemaphore(4)
        self.executor = ThreadPoolExecutor(max_workers=4, thread_name_prefix="farmable-account")

    async def call(self, function, *args):
        if not self.slots.acquire(blocking=False):
            raise ApiError(503, "capacity_unavailable", 1)
        try:
            future = self.executor.submit(partial(copy_context().run, function, *args))
        except BaseException:
            self.slots.release()
            raise
        # Cancellation does not release a slot while its thread is still running.
        future.add_done_callback(lambda _: self.slots.release())
        try:
            return await asyncio.wrap_future(future)
        except (OperationalError, DatabaseTimeout):
            raise ApiError(503, "dependency_unavailable", 5) from None

    def close(self) -> None:
        self.executor.shutdown(wait=True, cancel_futures=True)


bearer = HTTPBearer(auto_error=False, scheme_name="SessionBearer")
router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 503)},
)


def runtime(request: Request) -> AccountRuntime:
    value = getattr(request.app.state, "account", None)
    if value is None:
        raise ApiError(503, "account_unavailable")
    return value


def client_ip(request: Request) -> str:
    # Resolved once by SafeDefaultsMiddleware from its trusted proxy hops.
    return getattr(request.state, "client_ip", None) or client_address(request.scope)


@router.post("/auth/logout", status_code=204, operation_id="authLogout")
async def logout(request: Request) -> None:
    worker = runtime(request)
    await worker.call(worker.service.logout, token(request))


@router.post("/auth/revoke-all", status_code=204, operation_id="authRevokeAll")
async def revoke_all(request: Request) -> None:
    worker = runtime(request)
    await worker.call(worker.service.revoke_all, token(request))


@router.get("/account/profile", response_model=ProfileResponse, operation_id="getAccountProfile")
async def read_profile(request: Request, response: Response):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.service.profile, token(request))


@router.get(
    "/account/consents", response_model=list[ConsentResponse], operation_id="listAccountConsents"
)
async def list_consents(request: Request, response: Response):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.service.list_consents, token(request))


@router.put(
    "/account/consents/{consent_type}",
    response_model=ConsentResponse,
    operation_id="setAccountConsent",
)
async def update_consent(
    request: Request, response: Response, consent_type: str, payload: ConsentUpdate
):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(
        worker.service.set_consent,
        token(request),
        consent_type,
        payload.version,
        payload.granted,
    )


@router.patch(
    "/account/profile", response_model=ProfileResponse, operation_id="updateAccountProfile"
)
async def write_profile(request: Request, response: Response, payload: ProfileUpdate):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    key = request.headers.get("Idempotency-Key", "").strip() or None
    has_contact_change = payload.email is not None or payload.phone is not None
    if has_contact_change and (key is None or not 16 <= len(key) <= 200):
        raise ApiError(400, "idempotency_key_required")
    if key is not None and not 16 <= len(key) <= 200:
        raise ApiError(400, "idempotency_key_required")
    scope = ""
    request_fingerprint = None
    if key is not None:
        scope = str(await worker.call(worker.service.owner_id, token(request)))
        # The fingerprint can run scrypt; keep it on the bounded account executor.
        request_fingerprint = await worker.call(
            partial(idempotency_fingerprint, payload.model_dump(mode="json"), key=key)
        )
    return await worker.call(
        partial(
            worker.service.update_profile,
            token(request),
            payload,
            ip=client_ip(request),
            idempotency_key=key,
            idempotency_scope=scope,
            request_fingerprint=request_fingerprint,
        )
    )


@router.post(
    "/account/contact/confirm",
    response_model=ProfileResponse,
    operation_id="confirmAccountContactChange",
)
async def confirm_contact_change(
    request: Request, response: Response, payload: ContactChangeConfirm
):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    channel = Channel.EMAIL if payload.channel == "email" else Channel.PHONE
    return await worker.call(
        worker.service.confirm_contact_change, token(request), channel, payload.code
    )


@router.get("/account/farm", response_model=AccountFarmResponse, operation_id="getAccountFarm")
async def read_farm(request: Request, response: Response):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.service.farm, token(request))


@router.patch("/account/farm", response_model=AccountFarmResponse, operation_id="updateAccountFarm")
async def write_farm(request: Request, response: Response, payload: FarmUpdate):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.service.update_farm, token(request), payload)


@router.get(
    "/account/export",
    operation_id="exportAccount",
    response_class=Response,
    responses={200: {"content": {"application/json": {}, "application/zip": {}}}},
)
async def export_account(request: Request, format: Literal["json", "zip"] = "json") -> Response:
    worker = runtime(request)
    document = await worker.call(worker.service.export_document, token(request))
    if format == "zip":
        body, media_type = zip_bytes(document), "application/zip"
    else:
        body, media_type = json_bytes(document), "application/json"
    # The filename is a constant plus a validated literal suffix: no caller
    # input reaches the header, so no traversal or unsafe archive name exists.
    return Response(
        content=body,
        media_type=media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{EXPORT_BASENAME}.{format}"',
            "Cache-Control": "no-store",
        },
    )


@router.post(
    "/account/export/jobs",
    response_model=ExportJobCreateResponse,
    status_code=201,
    operation_id="createAccountExportJob",
)
async def create_export_job(
    request: Request, response: Response, format: Literal["json", "zip"] = "json"
):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    raw_key = request.headers.get("Idempotency-Key")
    key = raw_key.strip() if raw_key is not None else None
    if key is not None and not 16 <= len(key) <= 200:
        raise ApiError(400, "idempotency_key_required")
    body = {"format": format}
    scope = ""
    if key:
        scope = str(await worker.call(worker.service.owner_id, token(request)))
        request_fingerprint = await worker.call(partial(idempotency_fingerprint, body, key=key))
    else:
        request_fingerprint = None
    job_id, download_token = await worker.call(
        partial(
            worker.service.create_export_job,
            token(request),
            format,
            idempotency_key=key,
            idempotency_scope=scope,
            request_fingerprint=request_fingerprint,
        )
    )
    result = ExportJobCreateResponse(id=job_id, download_token=download_token)
    return result


@router.get(
    "/account/export/jobs/{job_id}",
    response_model=ExportJobStatusResponse,
    operation_id="getAccountExportJob",
)
async def read_export_job(request: Request, response: Response, job_id: UUID):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.service.export_job_status, token(request), job_id)


@router.get(
    "/account/export/jobs/{job_id}/download",
    operation_id="downloadAccountExportJob",
    response_class=Response,
    responses={200: {"content": {"application/json": {}, "application/zip": {}}}},
)
async def download_export_job(request: Request, job_id: UUID, token: str) -> Response:
    # Authorized by the download token alone, not the caller's own session
    # bearer: the link is meant to be usable on its own, short-lived and
    # single-purpose, matching issue #9's "expiring authorized download link".
    worker = runtime(request)
    body, media_type = await worker.call(worker.service.download_export_job, job_id, token)
    extension = "zip" if media_type == "application/zip" else "json"
    return Response(
        content=body,
        media_type=media_type,
        headers={
            "Content-Disposition": f'attachment; filename="{EXPORT_BASENAME}.{extension}"',
            "Cache-Control": "no-store",
        },
    )


@router.delete("/account", status_code=204, operation_id="deleteAccount")
async def delete_account(request: Request, payload: DeleteAccountRequest) -> None:
    worker = runtime(request)
    await worker.call(worker.service.delete_account, token(request), payload.password)
