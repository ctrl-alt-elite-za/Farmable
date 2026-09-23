"""Authenticated account, privacy and session routes. Owner scope is never a parameter."""

import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor
from contextvars import copy_context
from functools import partial
from typing import Literal

from fastapi import APIRouter, Depends, Request, Response
from fastapi.security import HTTPBearer
from sqlalchemy.exc import OperationalError
from sqlalchemy.exc import TimeoutError as DatabaseTimeout

from farmable_backend.account import EXPORT_BASENAME, AccountService, json_bytes, zip_bytes
from farmable_backend.account_schemas import (
    AccountFarmResponse,
    DeleteAccountRequest,
    FarmUpdate,
    ProfileResponse,
    ProfileUpdate,
)
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import token
from farmable_backend.schemas import ErrorResponse


class AccountRuntime:
    """Bounded off-loop admission for blocking account transactions and Argon2."""

    def __init__(self, service: AccountService):
        self.service = service
        self.slots = threading.BoundedSemaphore(4)
        self.export_slots = threading.BoundedSemaphore(1)
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

    async def call_export(self, authorization: str | None):
        if not self.export_slots.acquire(blocking=False):
            raise ApiError(429, "export_in_progress", 1)
        try:
            return await self.call(self.service.export_document, authorization)
        finally:
            self.export_slots.release()

    def close(self) -> None:
        self.executor.shutdown(wait=True, cancel_futures=True)


bearer = HTTPBearer(auto_error=False, scheme_name="SessionBearer")
router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 413, 429, 503)},
)


def runtime(request: Request) -> AccountRuntime:
    value = getattr(request.app.state, "account", None)
    if value is None:
        raise ApiError(503, "account_unavailable")
    return value


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


@router.patch(
    "/account/profile", response_model=ProfileResponse, operation_id="updateAccountProfile"
)
async def write_profile(request: Request, response: Response, payload: ProfileUpdate):
    response.headers["Cache-Control"] = "no-store"
    worker = runtime(request)
    return await worker.call(worker.service.update_profile, token(request), payload)


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
    document = await worker.call_export(token(request))
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


@router.delete("/account", status_code=204, operation_id="deleteAccount")
async def delete_account(request: Request, payload: DeleteAccountRequest) -> None:
    worker = runtime(request)
    await worker.call(worker.service.delete_account, token(request), payload.password)
