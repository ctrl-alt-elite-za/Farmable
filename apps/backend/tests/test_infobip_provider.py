"""Infobip SMS adapter results, and how an uncertain SMS send is handled at sign-up."""

import asyncio

import httpx
import pytest
from farmable_backend.infobip import InfobipOtpProvider
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from fastapi.testclient import TestClient
from test_auth_acceptance import _app, _signup_request


@pytest.mark.parametrize(
    "payload, ambiguous",
    [
        (
            {
                "messages": [
                    {
                        "to": "27820000000",
                        "messageId": "id",
                        "status": {"name": "REJECTED_NOT_ENOUGH_CREDITS"},
                    }
                ]
            },
            False,
        ),
        ({"messages": []}, True),
        ({"messages": [None]}, True),
        (
            {
                "messages": [
                    {"destination": "27820000000", "messageId": "id", "status": {"name": []}}
                ]
            },
            True,
        ),
        ({"messages": [{"to": "27820000000", "status": {"name": "PENDING_ACCEPTED"}}]}, True),
        (
            {
                "messages": [
                    {
                        "to": "27820000001",
                        "messageId": "id",
                        "status": {"name": "PENDING_ACCEPTED"},
                    }
                ]
            },
            True,
        ),
    ],
)
def test_infobip_rejects_unaccepted_or_malformed_sms_results(payload, ambiguous):
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
                assert result.ambiguous is ambiguous
            finally:
                await client.aclose()

    asyncio.run(run())


def test_uncertain_sms_response_keeps_signup_code_and_does_not_resend(settings, monkeypatch):
    app, auth, _, _ = _app(settings)
    sms_calls = 0

    def handler(request):
        nonlocal sms_calls
        if request.url.path.startswith("/email/"):
            return httpx.Response(200, json={"messages": []})  # The later email step.
        sms_calls += 1
        raise httpx.ReadTimeout("response lost", request=request)

    provider = InfobipOtpProvider(
        "abc123.api.infobip.com",
        "test-key",
        "Almanac",
        "codes@example.com",
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    monkeypatch.setattr(provider, "create_code", lambda channel: "123456")
    auth.provider = provider
    try:
        with TestClient(app) as client:
            key = "test-uncertain-sms-response-key"
            first = _signup_request(client, key=key)
            replay = _signup_request(client, key=key)
            assert first.status_code == replay.status_code == 503
            assert first.json()["error"]["code"] == "delivery_unknown"
            assert replay.json() == first.json()
            assert sms_calls == 1
            user_id = first.json()["error"]["user_id"]
            verified = client.post(
                "/auth/verify/phone", json={"user_id": user_id, "code": "123456"}
            )
            assert verified.status_code == 200
            assert sms_calls == 1
    finally:
        provider.close()


@pytest.mark.parametrize("recipient_field", ["destination", "to"])
def test_infobip_accepts_correlated_sms_acknowledgement(recipient_field):
    async def run():
        def handler(request):
            return httpx.Response(
                200,
                json={
                    "messages": [
                        {
                            recipient_field: "27820000000",
                            "messageId": "fixture-id",
                            "status": {"name": "PENDING_ACCEPTED"},
                        }
                    ]
                },
            )

        registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
        await registry.client.aclose()
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            registry.infobip.client = client
            result = await registry.infobip.send_sms("+27820000000", "fixture")
            assert result.ok and not result.ambiguous

    asyncio.run(run())


@pytest.mark.parametrize(
    "status, body, ambiguous",
    [
        (200, b"{", True),
        (200, b"[]", True),
        (502, b"upstream response lost", True),
        (400, b"bad request", False),
        (401, b"unauthorized", False),
        (429, b"rate limited", False),
    ],
)
def test_infobip_preserves_uncertain_response_outcome(status, body, ambiguous):
    async def run():
        calls = 0

        def handler(request):
            nonlocal calls
            calls += 1
            return httpx.Response(status, content=body)

        registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
        await registry.client.aclose()
        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            registry.infobip.client = client
            result = await registry.infobip.send_sms("+27820000000", "fixture")
            assert calls == 1
            assert not result.ok
            assert result.ambiguous is ambiguous

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
