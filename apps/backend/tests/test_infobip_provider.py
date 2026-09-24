"""LiveOtpProvider bridges the sync OtpProvider protocol to Infobip SMS + a pluggable email sender.

SMS goes through the async Infobip adapter; email goes through a fake
EmailSender so no real network call ever happens in this test module.
"""

import asyncio
import threading
from collections.abc import Iterator

import httpx
import pytest
from farmable_backend.auth import (
    EMAIL_DAILY_CAP_LIMIT,
    AuthError,
    Channel,
    LiveOtpProvider,
)
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from test_auth import _database_auth


class FakeEmailSender:
    def __init__(self, *, ok: bool = True):
        self.ok = ok
        self.calls: list[tuple[str, str, str, str]] = []

    def send(self, to: str, subject: str, html: str, text: str) -> bool:
        self.calls.append((to, subject, html, text))
        return self.ok


@pytest.fixture
def loop_thread() -> Iterator[asyncio.AbstractEventLoop]:
    """A real background event loop, mirroring the main-loop/executor-thread split in main.py."""
    loop = asyncio.new_event_loop()
    thread = threading.Thread(target=loop.run_forever, daemon=True)
    thread.start()
    try:
        yield loop
    finally:
        loop.call_soon_threadsafe(loop.stop)
        thread.join(timeout=5)
        loop.close()


def make_registry(loop: asyncio.AbstractEventLoop, **fault_kwargs) -> ServiceRegistry:
    async def build() -> ServiceRegistry:
        return ServiceRegistry(
            ServiceSettings(environment="ci", integrations_mode="fake", **fault_kwargs)
        )

    return asyncio.run_coroutine_threadsafe(build(), loop).result(timeout=5)


def close_registry(loop: asyncio.AbstractEventLoop, registry: ServiceRegistry) -> None:
    asyncio.run_coroutine_threadsafe(registry.close(), loop).result(timeout=5)


def test_deliver_sends_sms_from_a_worker_thread(loop_thread):
    registry = make_registry(loop_thread)
    sessions, _ = _database_auth()
    provider = LiveOtpProvider(registry.infobip, FakeEmailSender(), loop_thread, sessions)
    try:
        result: dict[str, object] = {}

        def worker():
            code = provider.create_code(Channel.PHONE)
            assert len(code) == 6 and code.isdigit()
            provider.deliver(Channel.PHONE, "+27820000000", code)
            result["ok"] = True

        thread = threading.Thread(target=worker)
        thread.start()
        thread.join(timeout=5)
        assert result.get("ok") is True
        assert registry.transport.calls["infobip"] == 1
    finally:
        close_registry(loop_thread, registry)


def test_deliver_sends_email_via_the_email_sender(loop_thread):
    registry = make_registry(loop_thread)
    sessions, _ = _database_auth()
    email_sender = FakeEmailSender()
    provider = LiveOtpProvider(registry.infobip, email_sender, loop_thread, sessions)
    try:
        provider.deliver(Channel.EMAIL, "farmer@example.test", "123456")
        assert len(email_sender.calls) == 1
        to, subject, html, text = email_sender.calls[0]
        assert to == "farmer@example.test"
        assert subject == "Your Almanac verification code"
        assert "123456" in html and "123456" in text
        assert not registry.transport.calls  # Email never touches the SMS adapter.
    finally:
        close_registry(loop_thread, registry)


def test_notify_existing_account_sends_a_warning(loop_thread):
    registry = make_registry(loop_thread)
    sessions, _ = _database_auth()
    provider = LiveOtpProvider(registry.infobip, FakeEmailSender(), loop_thread, sessions)
    try:

        def worker():
            provider.notify_existing_account(Channel.PHONE, "+27820000000")

        thread = threading.Thread(target=worker)
        thread.start()
        thread.join(timeout=5)
        assert registry.transport.calls["infobip"] == 1
    finally:
        close_registry(loop_thread, registry)


def test_sms_failure_raises_auth_error_without_leaking_provider_text(loop_thread):
    registry = make_registry(loop_thread, fault_infobip=True)
    sessions, _ = _database_auth()
    provider = LiveOtpProvider(registry.infobip, FakeEmailSender(), loop_thread, sessions)
    try:
        errors: list[AuthError] = []

        def worker():
            try:
                provider.deliver(Channel.PHONE, "+27820000000", "123456")
            except AuthError as error:
                errors.append(error)

        thread = threading.Thread(target=worker)
        thread.start()
        thread.join(timeout=5)
        assert len(errors) == 1
        assert errors[0].code == "provider_unavailable"
        assert errors[0].status_code == 503
        assert not registry.transport.calls
    finally:
        close_registry(loop_thread, registry)


def test_email_send_failure_raises_auth_error(loop_thread):
    registry = make_registry(loop_thread)
    sessions, _ = _database_auth()
    provider = LiveOtpProvider(registry.infobip, FakeEmailSender(ok=False), loop_thread, sessions)
    try:
        with pytest.raises(AuthError) as caught:
            provider.deliver(Channel.EMAIL, "farmer@example.test", "123456")
        assert caught.value.code == "provider_unavailable"
        assert caught.value.status_code == 503
    finally:
        close_registry(loop_thread, registry)


def test_email_daily_cap_blocks_further_sends(loop_thread):
    registry = make_registry(loop_thread)
    sessions, _ = _database_auth()
    email_sender = FakeEmailSender()
    provider = LiveOtpProvider(registry.infobip, email_sender, loop_thread, sessions)
    try:
        for _ in range(EMAIL_DAILY_CAP_LIMIT):
            provider.deliver(Channel.EMAIL, "farmer@example.test", "123456")
        assert len(email_sender.calls) == EMAIL_DAILY_CAP_LIMIT
        with pytest.raises(AuthError) as caught:
            provider.deliver(Channel.EMAIL, "farmer@example.test", "123456")
        assert caught.value.code == "provider_unavailable"
        # The capped attempt must not have reached the email sender at all.
        assert len(email_sender.calls) == EMAIL_DAILY_CAP_LIMIT
    finally:
        close_registry(loop_thread, registry)


@pytest.mark.parametrize(
    "payload",
    [
        {
            "messages": [
                {
                    "to": "27820000000",
                    "messageId": "id",
                    "status": {"name": "REJECTED_NOT_ENOUGH_CREDITS"},
                }
            ]
        },
        {"messages": []},
        {"messages": [{"to": "27820000000", "status": {"name": "PENDING_ACCEPTED"}}]},
        {
            "messages": [
                {
                    "to": "27820000001",
                    "messageId": "id",
                    "status": {"name": "PENDING_ACCEPTED"},
                }
            ]
        },
    ],
)
def test_infobip_rejects_unaccepted_or_malformed_sms_results(payload):
    async def run():
        async def handler(request: httpx.Request) -> httpx.Response:
            return httpx.Response(200, json=payload)

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
            await registry.client.aclose()
            registry.client = client
            registry.infobip.client = client
            try:
                result = await registry.infobip.send_sms("+27820000000", "fixture")
                assert not result.ok and result.error == "invalid_response"
            finally:
                await client.aclose()

    asyncio.run(run())


def test_infobip_does_not_retry_ambiguous_sms_delivery():
    async def run():
        calls = 0

        async def handler(request: httpx.Request) -> httpx.Response:
            nonlocal calls
            calls += 1
            raise httpx.ReadTimeout("response lost")

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
            await registry.client.aclose()
            registry.client = client
            registry.infobip.client = client
            try:
                result = await registry.infobip.send_sms("+27820000000", "fixture")
                assert calls == 1
                assert not result.ok and result.error == "delivery_unknown" and result.ambiguous
            finally:
                await client.aclose()

    asyncio.run(run())
