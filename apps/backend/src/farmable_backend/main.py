import os
from collections.abc import Callable
from contextlib import asynccontextmanager
from http import HTTPStatus

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from starlette.concurrency import run_in_threadpool
from starlette.exceptions import HTTPException

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.logging import configure_logging
from farmable_backend.middleware import RateLimiter, SafeDefaultsMiddleware, error_response
from farmable_backend.schemas import ErrorResponse, LiveResponse, ReadyResponse


def create_app(
    settings: Settings | None = None,
    readiness: Callable[[], dict[str, str]] | None = None,
    limiter: RateLimiter | None = None,
    service_settings: ServiceSettings | None = None,
) -> FastAPI:
    @asynccontextmanager
    async def lifespan(app: FastAPI):
        config = settings or Settings()
        configure_logging(config.log_level)
        services = ServiceRegistry(service_settings or ServiceSettings())
        app.state.services = services
        app.state.sha = config.commit_sha
        database = None
        try:
            database = None if readiness is not None else Database(config)
            if readiness is not None:
                app.state.readiness = readiness
            elif database is not None:
                app.state.readiness = database.readiness
            yield
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
    app.add_middleware(SafeDefaultsMiddleware, limiter=limiter or RateLimiter())

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
