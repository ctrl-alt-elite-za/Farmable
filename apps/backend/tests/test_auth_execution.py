"""Auth I/O must not block health checks or unboundedly fan out Argon2 work."""

import asyncio
import threading
from uuid import uuid4

import httpx
import pytest
from farmable_backend.auth import AuthError
from farmable_backend.logging import request_id
from farmable_backend.main import create_app


class BlockingAuth:
    def __init__(self, expected=1):
        self.expected = expected
        self.entered = threading.Event()
        self.release = threading.Event()
        self.lock = threading.Lock()
        self.active = 0
        self.maximum = 0
        self.correlations = []

    def call(self, *args):
        with self.lock:
            self.active += 1
            self.maximum = max(self.maximum, self.active)
            self.correlations.append(request_id.get())
            if self.active == self.expected:
                self.entered.set()
        try:
            if not self.release.wait(timeout=5):
                raise AssertionError("Auth was not released by the health probe")
            raise AuthError("invalid_credentials", 401)
        finally:
            with self.lock:
                self.active -= 1

    signup = verify = resend = login = refresh = call


@pytest.mark.parametrize(
    ("path", "payload"),
    [
        (
            "signup",
            {
                "first_name": "Test",
                "surname": "User",
                "phone": "+27820000000",
                "email": "test@example.com",
                "password": "synthetic test password",
            },
        ),
        ("verify/phone", {"user_id": str(uuid4()), "code": "123456"}),
        ("verify/email", {"user_id": str(uuid4()), "code": "123456"}),
        ("otp/resend", {"user_id": str(uuid4()), "channel": "phone"}),
        ("login", {"identifier": "test@example.com", "password": "synthetic"}),
        ("refresh", {"refresh_token": "synthetic-refresh-token-for-test"}),
    ],
)
def test_health_stays_responsive_during_auth(settings, path, payload):
    service = BlockingAuth()
    app = create_app(settings, readiness=lambda: {})
    app.state.auth = service
    correlation = str(uuid4())

    async def check():
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app), base_url="http://test"
        ) as client:
            pending = asyncio.create_task(
                client.post(f"/auth/{path}", json=payload, headers={"X-Request-ID": correlation})
            )
            try:
                assert await asyncio.to_thread(service.entered.wait, 3)
                response = await client.get("/health/live")
                assert response.status_code == 200
                assert not pending.done(), "Auth blocked the API event loop"
            finally:
                service.release.set()
                result = await pending
            assert result.status_code == 401
            assert service.correlations == [correlation]

    try:
        asyncio.run(check())
    finally:
        app.state.auth_executor.shutdown(wait=True, cancel_futures=True)


def test_auth_concurrency_is_bounded_without_blocking_health(settings):
    service = BlockingAuth(expected=2)
    app = create_app(settings, readiness=lambda: {})
    app.state.auth = service

    async def check():
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app), base_url="http://test"
        ) as client:
            pending = [
                asyncio.create_task(
                    client.post(
                        "/auth/login",
                        json={"identifier": "test@example.com", "password": "synthetic"},
                    )
                )
                for _ in range(3)
            ]
            try:
                assert await asyncio.to_thread(service.entered.wait, 3)
                assert (await client.get("/health/live")).status_code == 200
            finally:
                service.release.set()
                responses = await asyncio.gather(*pending)
            assert all(response.status_code == 401 for response in responses)
            assert service.maximum == 2

    try:
        asyncio.run(check())
    finally:
        app.state.auth_executor.shutdown(wait=True, cancel_futures=True)


def test_cancelling_requests_does_not_release_running_auth_worker_slots(settings):
    service = BlockingAuth(expected=2)
    app = create_app(settings, readiness=lambda: {})
    app.state.auth = service

    async def check():
        async with httpx.AsyncClient(
            transport=httpx.ASGITransport(app), base_url="http://test"
        ) as client:

            def login():
                return asyncio.create_task(
                    client.post(
                        "/auth/login",
                        json={"identifier": "test@example.com", "password": "synthetic"},
                    )
                )

            cancelled = [login(), login()]
            replacement = None
            try:
                assert await asyncio.to_thread(service.entered.wait, 3)
                for task in cancelled:
                    task.cancel()
                await asyncio.gather(*cancelled, return_exceptions=True)
                replacement = login()
                await asyncio.sleep(0.05)
                assert (await client.get("/health/live")).status_code == 200
                assert service.maximum == 2
            finally:
                service.release.set()
                await asyncio.gather(*cancelled, return_exceptions=True)
                if replacement is not None:
                    assert (await replacement).status_code == 401
            assert service.maximum == 2

    try:
        asyncio.run(check())
    finally:
        app.state.auth_executor.shutdown(wait=True, cancel_futures=True)
