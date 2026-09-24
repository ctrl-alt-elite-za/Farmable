import logging
import math
import threading
import time
from collections import deque
from collections.abc import Callable

from starlette.datastructures import Headers, MutableHeaders
from starlette.responses import JSONResponse
from starlette.types import ASGIApp, Message, Receive, Scope, Send

from farmable_backend.logging import correlation_id, request_id

logger = logging.getLogger(__name__)


def error_response(
    status: int, code: str, message: str, *, user_id: str | None = None, **kwargs
) -> JSONResponse:
    error = {"code": code, "message": message}
    if user_id is not None:
        error["user_id"] = user_id
    return JSONResponse({"error": error}, status_code=status, **kwargs)


class RateLimiter:
    """Sliding 60s window per peer IP. One API process; no trusted forwarding headers."""

    def __init__(self, clock: Callable[[], float] = time.monotonic, max_ips: int = 10_000):
        self.clock = clock
        self.max_ips = max_ips
        self.hits: dict[str, deque[float]] = {}
        self.lock = threading.Lock()
        self.last_cleanup = 0.0

    def retry_after(self, ip: str) -> int | None:
        with self.lock:
            now = self.clock()
            if now - self.last_cleanup >= 60:
                self.hits = {k: v for k, v in self.hits.items() if v[-1] > now - 60}
                self.last_cleanup = now
            if ip not in self.hits and len(self.hits) >= self.max_ips:
                return 60  # Fail closed rather than evicting an active limit.
            hits = self.hits.setdefault(ip, deque())
            while hits and hits[0] <= now - 60:
                hits.popleft()
            if len(hits) >= 120:
                return max(1, math.ceil(60 - (now - hits[0])))
            hits.append(now)
            return None


class SafeDefaultsMiddleware:
    def __init__(self, app: ASGIApp, limiter: RateLimiter):
        self.app = app
        self.limiter = limiter

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        rid = correlation_id(Headers(scope=scope).get("x-request-id"))
        context = request_id.set(rid)
        scope.setdefault("state", {})["request_id"] = rid
        started = False
        status = 500

        async def safe_send(message: Message) -> None:
            nonlocal started, status
            if message["type"] == "http.response.start":
                MutableHeaders(scope=message)["X-Request-ID"] = rid
                started = True
                status = message["status"]
            await send(message)

        try:
            peer = scope.get("client")
            retry_after = self.limiter.retry_after(peer[0] if peer else "unknown")
            if retry_after is not None:
                await error_response(
                    429,
                    "rate_limited",
                    "Too many requests",
                    headers={"Retry-After": str(retry_after)},
                )(scope, receive, safe_send)
            else:
                try:
                    await self.app(scope, receive, safe_send)
                except Exception:
                    logger.error("Unhandled request failure", exc_info=True)
                    if started:
                        raise
                    await error_response(500, "internal_error", "Internal server error")(
                        scope, receive, safe_send
                    )
        finally:
            logger.info("Request completed", extra={"fields": {"status": status}})
            request_id.reset(context)
