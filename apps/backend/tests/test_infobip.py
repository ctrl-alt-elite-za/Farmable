import json

import httpx
import pytest
from farmable_backend.auth import AuthError, Channel
from farmable_backend.infobip import InfobipOtpProvider, create_infobip_provider
from farmable_backend.integrations.settings import ServiceSettings
from pydantic import ValidationError

LIVE = {
    "environment": "staging",
    "integrations_mode": "live",
    "infobip_base_url": "abc123.api.infobip.com",
    "infobip_api_key": "test-key",
    "infobip_sms_sender": "Almanac",
    "infobip_email_sender": "codes@example.com",
}


def _provider(handler) -> tuple[InfobipOtpProvider, list[httpx.Request]]:
    seen: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    client = httpx.Client(transport=httpx.MockTransport(record))
    return (
        InfobipOtpProvider(
            "abc123.api.infobip.com", "test-key", "Almanac", "codes@example.com", client=client
        ),
        seen,
    )


def test_a_phone_code_is_sent_as_one_sms_to_the_digits_of_the_number():
    provider, seen = _provider(lambda _: httpx.Response(200, json={"messages": []}))
    provider.deliver(Channel.PHONE, "+27821234567", "123456")
    (request,) = seen
    assert str(request.url) == "https://abc123.api.infobip.com/sms/2/text/advanced"
    assert request.headers["Authorization"] == "App test-key"
    (message,) = json.loads(request.content)["messages"]
    assert message["destinations"] == [{"to": "27821234567"}]
    assert message["from"] == "Almanac"
    assert "123456" in message["text"]
    assert "10 minutes" in message["text"]


def test_an_email_code_is_sent_as_form_fields():
    provider, seen = _provider(lambda _: httpx.Response(200, json={"messages": []}))
    provider.deliver(Channel.EMAIL, "farmer@example.com", "654321")
    (request,) = seen
    assert str(request.url) == "https://abc123.api.infobip.com/email/3/send"
    assert request.headers["Content-Type"].startswith("multipart/form-data")
    body = request.content.decode()
    for field, value in (
        ("from", "codes@example.com"),
        ("to", "farmer@example.com"),
        ("subject", "Your Almanac verification code"),
    ):
        assert f'name="{field}"\r\n\r\n{value}\r\n' in body
    assert "654321" in body


@pytest.mark.parametrize("status", [400, 401, 429, 500])
def test_a_rejected_send_is_a_fixed_provider_error(status):
    provider, _ = _provider(lambda _: httpx.Response(status, text="test-key 123456 detail"))
    with pytest.raises(AuthError) as raised:
        provider.deliver(Channel.PHONE, "+27821234567", "123456")
    assert (raised.value.code, raised.value.status_code) == ("provider_error", 503)
    # Nothing from the provider, the key or the code leaks into the error.
    assert str(raised.value) == "provider_error"


def test_a_network_failure_is_a_fixed_provider_error():
    def fail(request):
        raise httpx.ConnectError("boom test-key", request=request)

    provider, _ = _provider(fail)
    with pytest.raises(AuthError) as raised:
        provider.deliver(Channel.EMAIL, "farmer@example.com", "123456")
    assert str(raised.value) == "provider_error"


@pytest.mark.parametrize("error", [httpx.ReadTimeout, httpx.ReadError, httpx.RemoteProtocolError])
def test_a_send_that_may_have_reached_infobip_is_delivery_unknown(error):
    def lost(request):
        raise error("response lost test-key", request=request)

    provider, seen = _provider(lost)
    with pytest.raises(AuthError) as raised:
        provider.deliver(Channel.PHONE, "+27821234567", "123456")
    assert (raised.value.code, raised.value.status_code) == ("delivery_unknown", 503)
    assert str(raised.value) == "delivery_unknown"
    assert len(seen) == 1


@pytest.mark.parametrize("channel", [Channel.PHONE, Channel.EMAIL])
def test_the_real_owner_is_warned_without_a_code(channel):
    provider, seen = _provider(lambda _: httpx.Response(200, json={"messages": []}))
    destination = "+27821234567" if channel is Channel.PHONE else "farmer@example.com"
    provider.notify_existing_account(channel, destination)
    (request,) = seen
    body = request.content.decode()
    assert "tried to use this" in body
    assert "verification code" not in body
    if channel is Channel.EMAIL:
        assert 'name="subject"\r\n\r\nAlmanac sign-up attempt\r\n' in body


def test_codes_are_six_random_digits():
    provider, _ = _provider(lambda _: httpx.Response(200))
    codes = {provider.create_code(Channel.PHONE) for _ in range(50)}
    assert all(len(code) == 6 and code.isdigit() for code in codes)
    assert len(codes) > 1


def test_infobip_is_used_only_when_live_and_fully_configured():
    provider = create_infobip_provider(ServiceSettings(**LIVE))
    assert isinstance(provider, InfobipOtpProvider)
    provider.close()
    for missing in (
        "infobip_base_url",
        "infobip_api_key",
        "infobip_sms_sender",
        "infobip_email_sender",
    ):
        partial = {key: value for key, value in LIVE.items() if key != missing}
        assert create_infobip_provider(ServiceSettings(**partial)) is None, missing
    assert create_infobip_provider(ServiceSettings(**{**LIVE, "integrations_mode": "fake"})) is None


def test_the_base_url_is_accepted_as_the_portal_shows_it():
    settings = ServiceSettings(**{**LIVE, "infobip_base_url": "https://ABC123.api.infobip.com/"})
    assert settings.infobip_base_url == "abc123.api.infobip.com"


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("infobip_base_url", "api.example.com"),
        ("infobip_base_url", "abc.api.infobip.com.evil.test"),
        ("infobip_sms_sender", "A sender name that is too long"),
        ("infobip_email_sender", "not-an-address"),
    ],
)
def test_malformed_infobip_values_are_refused(field, value):
    with pytest.raises(ValidationError):
        ServiceSettings(**{**LIVE, field: value})
