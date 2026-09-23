import asyncio
import os
from collections.abc import Callable
from concurrent.futures import ThreadPoolExecutor
from contextlib import asynccontextmanager
from contextvars import copy_context
from functools import partial
from http import HTTPStatus

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException

from farmable_backend.account import AccountService
from farmable_backend.account_api import AccountRuntime
from farmable_backend.account_api import router as account_router
from farmable_backend.assistant.api import router as assistant_router
from farmable_backend.assistant.live_api import router as assistant_live_router
from farmable_backend.assistant.runtime import Runtime as AssistantRuntime
from farmable_backend.assistant.settings import AssistantSettings
from farmable_backend.assistant.store import Store as AssistantStore
from farmable_backend.auth import (
    AuthError,
    AuthService,
    AuthUser,
    Channel,
    DeterministicFakeOtpProvider,
    SessionTokens,
)
from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.forecast_api import router as forecast_router
from farmable_backend.gcs_photos import create_gcs_photos
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.logging import configure_logging
from farmable_backend.middleware import RateLimiter, SafeDefaultsMiddleware, error_response
from farmable_backend.planning.api import router as planning_router
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import RecordBodyLimit, RecordRuntime
from farmable_backend.records_api import router as records_router
from farmable_backend.records_service import RecordsService
from farmable_backend.schemas import (
    AuthProgressResponse,
    ErrorResponse,
    LiveResponse,
    LoginRequest,
    ReadyResponse,
    RefreshRequest,
    ResendOtpRequest,
    SessionResponse,
    SignUpRequest,
    UserResponse,
    VerifyOtpRequest,
)
from farmable_backend.voice_api import router as voice_router


def _user_response(user: AuthUser) -> UserResponse:
    return UserResponse(
        id=user.id,
        first_name=user.first_name,
        surname=user.surname,
        phone=user.phone,
        email=user.email,
        phone_verified=user.phone_verified,
        email_verified=user.email_verified,
    )


def _session_response(tokens: SessionTokens) -> SessionResponse:
    return SessionResponse(
        access_token=tokens.access_token,
        refresh_token=tokens.refresh_token,
        expires_at=tokens.expires_at,
        user=_user_response(tokens.user),
    )


def create_app(
    settings: Settings | None = None,
    readiness: Callable[[], dict[str, str]] | None = None,
    limiter: RateLimiter | None = None,
    service_settings: ServiceSettings | None = None,
) -> FastAPI:
    # Argon2 uses significant memory per call. A dedicated bounded executor also
    # leaves the general thread pool available for readiness checks. Cancelled
    # HTTP requests cannot free a running thread's slot before its work finishes.
    auth_executor = ThreadPoolExecutor(max_workers=2, thread_name_prefix="farmable-auth")

    async def call_auth(function, *args):
        return await asyncio.get_running_loop().run_in_executor(
            auth_executor, partial(copy_context().run, function, *args)
        )

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        config = settings or Settings()
        configure_logging(config.log_level)
        integration_config = service_settings or ServiceSettings()
        services = ServiceRegistry(integration_config)
        app.state.services = services
        app.state.forecast_data_mode = config.forecast_data_mode
        app.state.sha = config.commit_sha
        database = None
        try:
            database = None if readiness is not None else Database(config)
            if readiness is not None:
                app.state.readiness = readiness
            elif database is not None:
                app.state.readiness = database.readiness
                provider = (
                    DeterministicFakeOtpProvider()
                    if integration_config.integrations_mode == "fake"
                    else None
                )
                app.state.auth = AuthService(database.sessions, provider)
                app.state.records = RecordRuntime(
                    RecordsService(database.sessions), lambda: create_gcs_photos(config)
                )
                app.state.account = AccountRuntime(AccountService(database.sessions))
                app.state.assistant = AssistantRuntime(
                    AssistantStore(database.sessions, AssistantSettings(), integration_config),
                    app.state.records,
                    services,
                    config.forecast_data_mode,
                )
            yield
        finally:
            try:
                # Drain uncancelled database work before disposing its pool.
                assistant = getattr(app.state, "assistant", None)
                if assistant is not None:
                    await assistant.close()
                await run_in_threadpool(auth_executor.shutdown, wait=True, cancel_futures=True)
                records = getattr(app.state, "records", None)
                if records is not None:
                    await run_in_threadpool(records.close)
                account = getattr(app.state, "account", None)
                if account is not None:
                    await run_in_threadpool(account.close)
            finally:
                try:
                    if database is not None:
                        database.close()
                finally:
                    await services.close()

    app = FastAPI(
        title="Farmable API",
        version="0.1.0",
        lifespan=lifespan,
        responses={
            422: {"model": ErrorResponse},
            429: {
                "model": ErrorResponse,
                "headers": {"Retry-After": {"schema": {"type": "integer"}}},
            },
            500: {"model": ErrorResponse},
        },
    )
    app.state.sha = settings.commit_sha if settings else os.getenv("COMMIT_SHA", "unknown")
    app.state.auth_executor = auth_executor
    app.add_middleware(RecordBodyLimit)
    app.add_middleware(SafeDefaultsMiddleware, limiter=limiter or RateLimiter())
    app.include_router(records_router)
    app.include_router(account_router)
    app.include_router(assistant_router)
    app.include_router(assistant_live_router)
    app.include_router(voice_router)
    app.include_router(forecast_router)
    app.include_router(planning_router)

    @app.exception_handler(ApiError)
    async def record_error(request: Request, exc: ApiError) -> JSONResponse:
        headers = {"Cache-Control": "no-store"}
        if exc.status == 401:
            headers["WWW-Authenticate"] = "Bearer"
        if exc.retry_after is not None:
            headers["Retry-After"] = str(exc.retry_after)
        return error_response(exc.status, exc.code, HTTPStatus(exc.status).phrase, headers=headers)

    @app.exception_handler(RequestValidationError)
    async def invalid_request(request: Request, exc: RequestValidationError) -> JSONResponse:
        return error_response(422, "validation_error", "Invalid request")

    @app.exception_handler(HTTPException)
    async def http_error(request: Request, exc: HTTPException) -> JSONResponse:
        # Do not reflect arbitrary exception details or request input.
        try:
            message = HTTPStatus(exc.status_code).phrase
        except ValueError:
            message = "Request failed"
        return error_response(exc.status_code, "http_error", message, headers=exc.headers)

    @app.exception_handler(AuthError)
    async def auth_error(request: Request, exc: AuthError) -> JSONResponse:
        messages = {
            "invalid_credentials": "Unable to log in with those details",
            "account_unverified": "Verify your phone and email before logging in",
            "account_exists": "An account already uses those details",
            "otp_rate_limited": "Please wait before requesting another code",
            "invalid_verification": "That verification code is not valid",
            "invalid_session": "Your session has expired",
            "provider_unavailable": "Verification is temporarily unavailable",
            "provider_error": "Verification is temporarily unavailable",
        }
        return error_response(exc.status_code, exc.code, messages.get(exc.code, "Request failed"))

    def auth(request: Request):
        service = getattr(request.app.state, "auth", None)
        if service is None:
            raise HTTPException(503)
        return service

    @app.post("/auth/signup", response_model=AuthProgressResponse, operation_id="authSignup")
    async def signup(request: Request, payload: SignUpRequest) -> AuthProgressResponse:
        user = await call_auth(
            auth(request).signup,
            payload.first_name,
            payload.surname,
            payload.phone,
            str(payload.email),
            payload.password,
        )
        return AuthProgressResponse(user_id=user.id, next_step="phone")

    @app.post(
        "/auth/verify/phone", response_model=AuthProgressResponse, operation_id="authVerifyPhone"
    )
    async def verify_phone(request: Request, payload: VerifyOtpRequest) -> AuthProgressResponse:
        await call_auth(auth(request).verify, payload.user_id, Channel.PHONE, payload.code)
        return AuthProgressResponse(user_id=payload.user_id, next_step="email")

    @app.post("/auth/verify/email", response_model=SessionResponse, operation_id="authVerifyEmail")
    async def verify_email(request: Request, payload: VerifyOtpRequest) -> SessionResponse:
        tokens = await call_auth(auth(request).verify, payload.user_id, Channel.EMAIL, payload.code)
        if not isinstance(tokens, SessionTokens):
            raise HTTPException(400)
        return _session_response(tokens)

    @app.post("/auth/otp/resend", status_code=204, operation_id="authResendOtp")
    async def resend_otp(request: Request, payload: ResendOtpRequest) -> None:
        await call_auth(auth(request).resend, payload.user_id, Channel(payload.channel))

    @app.post("/auth/login", response_model=SessionResponse, operation_id="authLogin")
    async def login(request: Request, payload: LoginRequest) -> SessionResponse:
        return _session_response(
            await call_auth(auth(request).login, payload.identifier, payload.password)
        )

    @app.post("/auth/refresh", response_model=SessionResponse, operation_id="authRefresh")
    async def refresh(request: Request, payload: RefreshRequest) -> SessionResponse:
        return _session_response(await call_auth(auth(request).refresh, payload.refresh_token))

    @app.get("/health/live", response_model=LiveResponse, operation_id="healthLive")
    async def live(request: Request) -> LiveResponse:
        return LiveResponse(sha=request.app.state.sha)

    @app.get(
        "/health/ready",
        response_model=ReadyResponse,
        operation_id="healthReady",
        responses={503: {"model": ReadyResponse, "description": "Dependency unavailable"}},
    )
    async def ready(request: Request) -> JSONResponse:
        try:
            status = await run_in_threadpool(request.app.state.readiness)
        except Exception:
            status = {"database": "down", "worker": "down"}
        response = ReadyResponse(**status, sha=request.app.state.sha)
        return JSONResponse(
            response.model_dump(),
            status_code=200 if all(v == "ok" for v in status.values()) else 503,
        )

    return app


app = create_app()
