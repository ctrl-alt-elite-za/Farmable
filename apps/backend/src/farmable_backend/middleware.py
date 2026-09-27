import ipaddress
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


def client_address(scope: Scope, trusted_proxy_hops: int = 0) -> str:
    """Return the caller address used for abuse limits.

    With no trusted proxy the socket peer is the caller. Behind ``n`` trusted
    proxies that each append the address they received the request from, the
    ``n``th X-Forwarded-For entry from the right is the address the outermost
    trusted proxy saw. Entries further left are client-supplied and ignored, so
    a spoofed header cannot choose its own bucket. A missing or malformed
    trusted entry falls back to the peer: one shared bucket, never a spoofed one.
    """
    peer = scope.get("client")
    fallback = peer[0] if peer else "unknown"
    if trusted_proxy_hops <= 0:
        return fallback
    entries = [
        entry.strip()
        for value in Headers(scope=scope).getlist("x-forwarded-for")
        for entry in value.split(",")
    ]
    if len(entries) < trusted_proxy_hops:
        return fallback
    try:
        return str(ipaddress.ip_address(entries[-trusted_proxy_hops]))
    except ValueError:
        return fallback


class RateLimiter:
    """Sliding 60s window per caller address (see ``client_address``)."""

    def __init__(
        self,
        clock: Callable[[], float] = time.monotonic,
        max_ips: int = 10_000,
        limit: int = 120,
    ):
        self.clock = clock
        self.max_ips = max_ips
        self.limit = limit
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
            if len(hits) >= self.limit:
                return max(1, math.ceil(60 - (now - hits[0])))
            hits.append(now)
            return None


# One map screen asks for dozens of tiles at once. They get their own, larger
# budget so a map can neither be starved by nor starve the rest of the app.
TILE_PATH_PREFIX = "/maps/tiles/"
TILES_PER_MINUTE = 900


class SafeDefaultsMiddleware:
    def __init__(
        self,
        app: ASGIApp,
        limiter: RateLimiter,
        trusted_proxy_hops: int = 0,
        tile_limiter: RateLimiter | None = None,
    ):
        self.app = app
        self.limiter = limiter
        self.trusted_proxy_hops = trusted_proxy_hops
        self.tile_limiter = tile_limiter or RateLimiter(limit=TILES_PER_MINUTE)

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        rid = correlation_id(Headers(scope=scope).get("x-request-id"))
        context = request_id.set(rid)
        ip = client_address(scope, self.trusted_proxy_hops)
        state = scope.setdefault("state", {})
        state["request_id"] = rid
        state["client_ip"] = ip
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
            limiter = (
                self.tile_limiter
                if str(scope.get("path", "")).startswith(TILE_PATH_PREFIX)
                else self.limiter
            )
            retry_after = limiter.retry_after(ip)
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
            # A map screen is dozens of tile requests; only failed ones are worth a line.
            tile = str(scope.get("path", "")).startswith(TILE_PATH_PREFIX)
            logger.log(
                logging.DEBUG if tile and status < 400 else logging.INFO,
                "Request completed",
                extra={"fields": {"status": status}},
            )
            request_id.reset(context)
