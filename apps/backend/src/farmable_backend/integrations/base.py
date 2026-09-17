"""Bounded calls and per-service circuit breakers; never expose provider exception text."""

import asyncio
import json
import secrets
import time
from collections.abc import AsyncGenerator, Awaitable, Callable
from dataclasses import dataclass, field
from typing import Any

import httpx
from pydantic import SecretStr

from .settings import TIMEOUTS, ServiceSettings


@dataclass(frozen=True)
class ServiceResult:
    service: str
    ok: bool
    error: str | None = None
    status: int | None = None
    data: dict[str, Any] | None = field(default=None, repr=False)
    audio: bytes | None = field(default=None, repr=False)
    done: bool = False


class ProviderFailure(Exception):
    def __init__(self, error: str, status: int | None = None):
        super().__init__(error)  # Fixed codes only, never response bodies/URLs/credentials.
        self.error, self.status = error, status

    @property
    def retryable(self) -> bool:
        return (
            self.error in {"network", "timeout"}
            or self.status == 429
            or (self.status is not None and 500 <= self.status <= 599)
        )


class Adapter:
    def __init__(
        self,
        service: str,
        client: httpx.AsyncClient,
        settings: ServiceSettings,
        *,
        timeout: float | None = None,
        clock: Callable[[], float] = time.monotonic,
        sleep: Callable[[float], Awaitable[None]] = asyncio.sleep,
        jitter: Callable[[], float] = lambda: secrets.randbelow(251) / 1000,
        max_attempts: int = 3,
    ):
        if not 1 <= max_attempts <= 3:
            raise ValueError("Attempts must be between one and three")
        self.max_attempts = max_attempts
        self.service, self.client, self.settings = service, client, settings
        self.timeout = TIMEOUTS[service] if timeout is None else timeout
        self.clock, self.sleep, self.jitter = clock, sleep, jitter
        self.failures = 0
        self.opened_at: float | None = None
        self.probe_task: asyncio.Task[Any] | None = None
        self.lock = asyncio.Lock()

    def failure(
        self, error: str, status: int | None = None, *, done: bool = False
    ) -> ServiceResult:
        return ServiceResult(self.service, False, error=error, status=status, done=done)

    def secret(self, value: SecretStr | None) -> str | None:
        if self.settings.integrations_mode == "fake":
            return "fixture-key"
        return value.get_secret_value() if value and value.get_secret_value() else None

    async def permit(self) -> bool:
        if self.settings.integrations_mode == "disabled" or self.settings.fault(self.service):
            return False
        async with self.lock:
            if self.opened_at is not None:
                if self.clock() - self.opened_at < 30 or self.probe_task is not None:
                    return False
                self.probe_task = asyncio.current_task()
            return True

    async def record(self, success: bool) -> None:
        async with self.lock:
            if self.probe_task is asyncio.current_task():
                self.probe_task = None
            if success:
                self.failures, self.opened_at, self.probe_task = 0, None, None
            else:
                self.failures += 1
                if self.failures >= 5:
                    self.opened_at = self.clock()

    async def release(self) -> None:
        # A cancelled consumer must not wedge a half-open probe or count as a provider failure.
        async with self.lock:
            if self.probe_task is asyncio.current_task():
                self.probe_task = None

    @staticmethod
    def check_status(response: httpx.Response) -> None:
        if not 200 <= response.status_code < 300:
            raise ProviderFailure("http", response.status_code)

    async def response(self, request: httpx.Request, binary: bool) -> ServiceResult:
        response = await self.client.send(request, stream=True)
        try:
            self.check_status(response)
            parts: list[bytes] = []
            size = 0
            async for part in response.aiter_bytes():
                size += len(part)
                if size > (10 * 1024 * 1024 if binary else 2 * 1024 * 1024):
                    raise ProviderFailure("invalid_response")
                parts.append(part)
            body = b"".join(parts)
            if binary:
                if not body:
                    raise ProviderFailure("invalid_response")
                return ServiceResult(self.service, True, status=response.status_code, audio=body)
            payload = json.loads(body)
            if not isinstance(payload, dict):
                raise ProviderFailure("invalid_response")
            return ServiceResult(self.service, True, status=response.status_code, data=payload)
        finally:
            await response.aclose()

    async def call(self, request: httpx.Request, *, binary: bool = False) -> ServiceResult:
        if not await self.permit():
            return self.failure("unavailable")
        try:
            failure = ProviderFailure("unavailable")
            for attempt in range(self.max_attempts):
                try:
                    async with asyncio.timeout(self.timeout):
                        result = await self.response(request, binary)
                    await self.record(True)
                    return result
                except (httpx.TimeoutException, TimeoutError):
                    failure = ProviderFailure("timeout")
                except httpx.TransportError:
                    failure = ProviderFailure("network")
                except (json.JSONDecodeError, UnicodeDecodeError, httpx.DecodingError):
                    failure = ProviderFailure("invalid_response")
                except ProviderFailure as error:
                    failure = error
                if not failure.retryable or attempt == self.max_attempts - 1:
                    break
                await self.sleep(0.5 * 2**attempt + self.jitter())
            await self.record(False)
            return self.failure(failure.error, failure.status)
        finally:
            await self.release()

    async def sse(self, request: httpx.Request) -> AsyncGenerator[dict[str, Any], None]:
        response = await self.client.send(request, stream=True)
        try:
            self.check_status(response)
            lines: list[str] = []
            size = 0
            async for line in response.aiter_lines():
                if line.startswith("data:"):
                    part = line[5:].lstrip()
                    size += len(part)
                    if size > 1024 * 1024:
                        raise ProviderFailure("invalid_response")
                    lines.append(part)
                elif not line and lines:
                    payload = json.loads("\n".join(lines))
                    if not isinstance(payload, dict):
                        raise ProviderFailure("invalid_response")
                    yield payload
                    lines, size = [], 0
            if lines:
                payload = json.loads("\n".join(lines))
                if not isinstance(payload, dict):
                    raise ProviderFailure("invalid_response")
                yield payload
        finally:
            await response.aclose()

    async def stream(
        self,
        request: httpx.Request,
        *,
        first_text_timeout: float = 10,
        has_text: Callable[[dict[str, Any]], bool],
    ) -> AsyncGenerator[ServiceResult, None]:
        if not await self.permit():
            yield self.failure("unavailable", done=True)
            return
        emitted = False
        started = self.clock()
        try:
            failure = ProviderFailure("unavailable")
            for attempt in range(self.max_attempts):
                iterator = self.sse(request)
                first_text = False
                try:
                    while True:
                        elapsed = self.clock() - started
                        budget = self.timeout - elapsed
                        if not first_text:
                            budget = min(budget, first_text_timeout - elapsed)
                        if budget <= 0:
                            raise TimeoutError
                        async with asyncio.timeout(budget):
                            payload = await anext(iterator)
                        first_text = first_text or has_text(payload)
                        emitted = True
                        yield ServiceResult(self.service, True, data=payload)
                except StopAsyncIteration:
                    if first_text:
                        await self.record(True)
                        yield ServiceResult(self.service, True, done=True)
                        return
                    failure = ProviderFailure("invalid_response")
                except (httpx.TimeoutException, TimeoutError):
                    failure = ProviderFailure("timeout")
                except httpx.TransportError:
                    failure = ProviderFailure("network")
                except (json.JSONDecodeError, UnicodeDecodeError, httpx.DecodingError):
                    failure = ProviderFailure("invalid_response")
                except ProviderFailure as error:
                    failure = error
                finally:
                    await iterator.aclose()
                if emitted or not failure.retryable or attempt == self.max_attempts - 1:
                    break
                remaining = min(self.timeout, first_text_timeout) - (self.clock() - started)
                delay = 0.5 * 2**attempt + self.jitter()
                if delay >= remaining:
                    failure = ProviderFailure("timeout")
                    break
                await self.sleep(delay)
            await self.record(False)
            yield self.failure(failure.error, failure.status, done=True)
        finally:
            await self.release()
