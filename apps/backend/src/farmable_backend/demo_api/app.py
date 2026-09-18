"""Provisional local demo API. Run separately; never mount into production main.py."""

import hashlib
import json
import os
from collections.abc import Callable
from contextlib import asynccontextmanager
from http import HTTPStatus
from pathlib import Path
from typing import Annotated
from uuid import UUID, uuid4

from fastapi import Depends, FastAPI, Header
from fastapi.exceptions import RequestValidationError
from fastapi.responses import FileResponse
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from starlette.datastructures import MutableHeaders
from starlette.exceptions import HTTPException
from starlette.middleware.cors import CORSMiddleware
from starlette.responses import JSONResponse, Response
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from farmable_backend.logging import configure_logging
from farmable_backend.middleware import RateLimiter, SafeDefaultsMiddleware, error_response
from farmable_backend.planning import PlanningResult, plan_section
from farmable_backend.planning.schemas import DemoModel, Identifier
from farmable_backend.schemas import ErrorResponse

from .init import database_path
from .schemas import (
    Dashboard,
    DemoFarm,
    DemoSection,
    DemoSession,
    EmptyRequest,
    Operation,
    PlanInputs,
    PlanWrite,
    SavedPlan,
    SectionWrite,
)
from .storage import DemoError, DemoStore, dashboard, seed_farm
from .voice import VoiceRequest, VoiceResponse, interpret


class DemoSafetyMiddleware:
    """Bound actual request bodies and prevent browser/proxy caching of session data."""

    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return

        async def safe_send(message: Message) -> None:
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)["Cache-Control"] = "no-store"
            await send(message)

        if scope["method"] in {"POST", "PUT", "PATCH"}:
            chunks: list[bytes] = []
            size = 0
            while True:
                message = await receive()
                if message["type"] == "http.disconnect":
                    return
                body = message.get("body", b"")
                size += len(body)
                if size > 65_536:
                    await error_response(413, "request_too_large", "Demo request exceeds 64 KiB")(
                        scope, receive, safe_send
                    )
                    return
                chunks.append(body)
                if not message.get("more_body", False):
                    break
            pending = True

            async def replay() -> Message:
                nonlocal pending
                if pending:
                    pending = False
                    return {"type": "http.request", "body": b"".join(chunks), "more_body": False}
                return await receive()

            await self.app(scope, replay, safe_send)
        else:
            await self.app(scope, receive, safe_send)


class NoStoreMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        async def safe_send(message: Message) -> None:
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)["Cache-Control"] = "no-store"
            await send(message)

        await self.app(scope, receive, safe_send)


def _section(farm: DemoFarm, section_id: UUID) -> DemoSection:
    for section in farm.sections:
        if section.id == section_id:
            return section
    raise DemoError(404, "section_not_found", "Section not found in this demo farm")


def _plan(farm: DemoFarm, plan_id: UUID) -> SavedPlan:
    for plan in farm.plans:
        if plan.id == plan_id:
            return plan
    raise DemoError(404, "plan_not_found", "Plan not found in this demo farm")


def _mutate(
    store: DemoStore,
    token: str,
    key: str,
    action: str,
    payload: DemoModel,
    change: Callable[[DemoFarm], tuple[DemoFarm, UUID]],
) -> tuple[DemoFarm, UUID]:
    fingerprint = hashlib.sha256(
        json.dumps(
            {"action": action, "payload": payload.model_dump(mode="json")},
            sort_keys=True,
            separators=(",", ":"),
        ).encode()
    ).hexdigest()
    resource_id: UUID | None = None

    def apply(farm: DemoFarm) -> DemoFarm:
        nonlocal resource_id
        for operation in farm.operations:
            if operation.key == key:
                if operation.fingerprint != fingerprint:
                    raise DemoError(409, "idempotency_conflict", "Use a new key for changed inputs")
                resource_id = operation.resource_id
                return farm
        if len(farm.operations) >= 100 and action != "reset":
            raise DemoError(409, "demo_operation_limit", "Reset this demo farm before continuing")
        updated, resource_id = change(farm)
        return updated.model_copy(
            update={
                "operations": (
                    *updated.operations,
                    Operation(
                        key=key,
                        fingerprint=fingerprint,
                        resource_id=resource_id,
                    ),
                )
            }
        )

    farm = store.update(token, apply)
    if resource_id is None:
        raise RuntimeError("Missing demo operation result")
    return farm, resource_id


def _propose(
    farm: DemoFarm, section_id: UUID, payload: PlanWrite, parent: UUID | None = None
) -> tuple[DemoFarm, UUID]:
    section = _section(farm, section_id)
    if len(farm.plans) >= 40:
        raise DemoError(409, "demo_plan_limit", "Reset this demo farm before creating more plans")
    result = plan_section(payload.for_section(str(section.id), section.area_m2))
    if not result.feasible:
        if result.reason is None:
            raise RuntimeError("Missing planning failure reason")
        raise DemoError(422, result.reason.code, result.reason.message)
    if payload.selection_index >= len(result.plans):
        raise DemoError(
            422, "selection_unavailable", "Choose an allocation returned by this preview"
        )
    saved = SavedPlan(
        id=uuid4(),
        section_id=section.id,
        section_revision=section.revision,
        version=1 + max((p.version for p in farm.plans if p.section_id == section_id), default=0),
        parent_plan_id=parent,
        result=result,
        selection_index=payload.selection_index,
    )
    return farm.model_copy(update={"plans": (*farm.plans, saved)}), saved.id


def create_demo_app(
    path: Path | None = None,
    origins: tuple[str, ...] | None = None,
    limiter: RateLimiter | None = None,
) -> FastAPI:
    allowed = (
        origins
        if origins is not None
        else tuple(
            origin.strip()
            for origin in os.getenv(
                "FARMABLE_DEMO_ORIGINS", "http://localhost:5173,http://127.0.0.1:5173"
            ).split(",")
            if origin.strip()
        )
    )
    if any(origin == "*" or not origin.startswith(("http://", "https://")) for origin in allowed):
        raise ValueError("Configure explicit frontend origins, not a wildcard")
    active_store: DemoStore | None = None

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        nonlocal active_store
        configure_logging()
        active_store = DemoStore(path or database_path())
        try:
            yield
        finally:
            active_store.close()
            active_store = None

    app = FastAPI(
        title="Farmable LOCAL SYNTHETIC DEMO API",
        version="0.1.0-prototype",
        description=(
            "Provisional contracts. Synthetic data only. "
            "Not production authentication/readiness."
        ),
        lifespan=lifespan,
        responses={code: {"model": ErrorResponse} for code in (401, 404, 409, 413, 422, 429, 500)},
    )
    app.add_middleware(DemoSafetyMiddleware)
    app.add_middleware(SafeDefaultsMiddleware, limiter=limiter or RateLimiter())
    app.add_middleware(NoStoreMiddleware)
    app.add_middleware(
        CORSMiddleware,
        allow_origins=list(allowed),
        allow_methods=["GET", "POST", "PUT", "DELETE"],
        allow_headers=[
            "Authorization",
            "Content-Type",
            "Idempotency-Key",
            "X-Request-ID",
            "Section-Revision",
        ],
        expose_headers=["X-Request-ID"],
    )

    def store() -> DemoStore:
        if active_store is None:
            raise RuntimeError("Demo storage is not running")
        return active_store

    bearer = HTTPBearer(auto_error=False)

    def session_token(
        credentials: Annotated[HTTPAuthorizationCredentials | None, Depends(bearer)],
    ) -> str:
        if credentials is None:
            raise DemoError(401, "invalid_demo_session", "Create or restore a demo session")
        return credentials.credentials

    Token = Annotated[str, Depends(session_token)]
    Key = Annotated[Identifier, Header(alias="Idempotency-Key")]

    @app.exception_handler(DemoError)
    async def demo_error(request, exc: DemoError) -> JSONResponse:
        return error_response(exc.status, exc.code, exc.message)

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request, exc: RequestValidationError) -> JSONResponse:
        return error_response(422, "validation_error", "Invalid request")

    @app.exception_handler(HTTPException)
    async def http_error(request, exc: HTTPException) -> JSONResponse:
        return error_response(exc.status_code, "http_error", HTTPStatus(exc.status_code).phrase)

    @app.get("/health/live")
    def live() -> dict[str, str]:
        return {"status": "ok", "mode": "local_synthetic_demo"}

    @app.get("/demo/voice", include_in_schema=False)
    def voice_page() -> FileResponse:
        return voice_asset("index.html", "text/html")

    def voice_asset(filename: str, media_type: str) -> FileResponse:
        return FileResponse(
            Path(__file__).parent / "web" / filename,
            media_type=media_type,
            headers={
                "Content-Security-Policy": (
                    "default-src 'none'; script-src 'self'; style-src 'self'; "
                    "connect-src 'self'; base-uri 'none'; "
                    "frame-ancestors 'none'; form-action 'none'"
                ),
                "X-Content-Type-Options": "nosniff",
                "Referrer-Policy": "no-referrer",
            },
        )

    @app.get("/demo/voice/assets/{filename}", include_in_schema=False)
    def voice_file(filename: str) -> FileResponse:
        # A fixed allowlist, never arbitrary paths or credentials from the local filesystem.
        if filename not in {"app.mjs", "speech.mjs", "style.css"}:
            raise DemoError(404, "asset_not_found", "Demo asset not found")
        return voice_asset(filename, "text/css" if filename.endswith(".css") else "text/javascript")

    @app.post("/demo/sessions", response_model=DemoSession, status_code=201)
    def start(payload: EmptyRequest) -> DemoSession:
        token, farm = store().create()
        return DemoSession(access_token=token, dashboard=dashboard(farm))

    @app.get("/demo/farm", response_model=Dashboard)
    def farm(token: Token) -> Dashboard:
        return dashboard(store().read(token))

    @app.get("/demo/sections/{section_id}", response_model=DemoSection)
    def get_section(section_id: UUID, token: Token) -> DemoSection:
        return _section(store().read(token), section_id)

    @app.post("/demo/sections", response_model=DemoSection, status_code=201)
    def create_section(payload: SectionWrite, token: Token, key: Key) -> DemoSection:
        def change(farm: DemoFarm) -> tuple[DemoFarm, UUID]:
            if len(farm.sections) >= 20:
                raise DemoError(
                    409, "demo_section_limit", "The demo supports at most twenty sections"
                )
            section = DemoSection(
                id=uuid4(),
                name=payload.name.strip(),
                area_m2=payload.resolved_area(),
                boundary=payload.boundary,
                area_source="boundary_estimate" if payload.boundary else "farmer_supplied",
            )
            return farm.model_copy(update={"sections": (*farm.sections, section)}), section.id

        updated, identifier = _mutate(store(), token, key, "create_section", payload, change)
        return _section(updated, identifier)

    @app.put("/demo/sections/{section_id}", response_model=DemoSection)
    def edit_section(
        section_id: UUID,
        payload: SectionWrite,
        token: Token,
        key: Key,
        expected_revision: Annotated[int, Header(alias="Section-Revision", ge=1)],
    ) -> DemoSection:
        # Include revision in the fingerprint so reusing a key cannot mask a changed precondition.
        def change(farm: DemoFarm) -> tuple[DemoFarm, UUID]:
            old = _section(farm, section_id)
            if old.revision != expected_revision:
                raise DemoError(409, "stale_section", "Reload the section before editing it")
            edited = old.model_copy(
                update={
                    "name": payload.name.strip(),
                    "area_m2": payload.resolved_area(),
                    "boundary": payload.boundary,
                    "area_source": "boundary_estimate" if payload.boundary else "farmer_supplied",
                    "revision": old.revision + 1,
                    "planned_plan_id": None,
                }
            )
            return farm.model_copy(
                update={
                    "sections": tuple(edited if s.id == section_id else s for s in farm.sections)
                }
            ), section_id

        updated, identifier = _mutate(
            store(), token, key, f"edit_section/{section_id}/{expected_revision}", payload, change
        )
        return _section(updated, identifier)

    @app.delete("/demo/sections/{section_id}", status_code=204)
    def delete_section(section_id: UUID, token: Token, key: Key) -> Response:
        def change(farm: DemoFarm) -> tuple[DemoFarm, UUID]:
            _section(farm, section_id)
            return farm.model_copy(
                update={
                    "sections": tuple(s for s in farm.sections if s.id != section_id),
                    "plans": tuple(p for p in farm.plans if p.section_id != section_id),
                }
            ), section_id

        _mutate(store(), token, key, f"delete_section/{section_id}", EmptyRequest(), change)
        return Response(status_code=204)

    @app.post("/demo/sections/{section_id}/preview", response_model=PlanningResult)
    def preview(section_id: UUID, payload: PlanInputs, token: Token) -> PlanningResult:
        section = _section(store().read(token), section_id)
        return plan_section(payload.for_section(str(section.id), section.area_m2))

    @app.post("/demo/sections/{section_id}/voice-preview", response_model=VoiceResponse)
    def voice_preview(section_id: UUID, payload: VoiceRequest, token: Token) -> VoiceResponse:
        section = _section(store().read(token), section_id)
        return interpret(payload, section)

    @app.post("/demo/sections/{section_id}/plans", response_model=SavedPlan, status_code=201)
    def propose(section_id: UUID, payload: PlanWrite, token: Token, key: Key) -> SavedPlan:
        updated, identifier = _mutate(
            store(),
            token,
            key,
            f"propose/{section_id}",
            payload,
            lambda farm: _propose(farm, section_id, payload),
        )
        return _plan(updated, identifier)

    @app.post("/demo/plans/{plan_id}/constraints", response_model=SavedPlan, status_code=201)
    def replan(plan_id: UUID, payload: PlanWrite, token: Token, key: Key) -> SavedPlan:
        def change(farm: DemoFarm) -> tuple[DemoFarm, UUID]:
            previous = _plan(farm, plan_id)
            return _propose(farm, previous.section_id, payload, previous.id)

        updated, identifier = _mutate(store(), token, key, f"replan/{plan_id}", payload, change)
        return _plan(updated, identifier)

    @app.get("/demo/plans/{plan_id}", response_model=SavedPlan)
    def get_plan(plan_id: UUID, token: Token) -> SavedPlan:
        return _plan(store().read(token), plan_id)

    @app.post("/demo/plans/{plan_id}/approve", response_model=SavedPlan)
    def approve(plan_id: UUID, payload: EmptyRequest, token: Token, key: Key) -> SavedPlan:
        def change(farm: DemoFarm) -> tuple[DemoFarm, UUID]:
            saved = _plan(farm, plan_id)
            section = _section(farm, saved.section_id)
            if section.revision != saved.section_revision:
                raise DemoError(
                    409, "stale_section", "The section changed; create a new plan before approval"
                )
            approved = saved.model_copy(update={"status": "approved"})
            return farm.model_copy(
                update={
                    "plans": tuple(approved if p.id == plan_id else p for p in farm.plans),
                    "sections": tuple(
                        s.model_copy(update={"planned_plan_id": plan_id})
                        if s.id == saved.section_id
                        else s
                        for s in farm.sections
                    ),
                }
            ), plan_id

        updated, identifier = _mutate(store(), token, key, f"approve/{plan_id}", payload, change)
        saved = _plan(updated, identifier)
        if _section(updated, saved.section_id).revision != saved.section_revision:
            raise DemoError(
                409, "stale_section", "The section changed; create a new plan before approval"
            )
        return saved

    @app.post("/demo/reset", response_model=Dashboard)
    def reset(payload: EmptyRequest, token: Token, key: Key) -> Dashboard:
        updated, _ = _mutate(
            store(), token, key, "reset", payload, lambda farm: (seed_farm(farm.id), farm.id)
        )
        return dashboard(updated)

    return app


app = create_demo_app()
