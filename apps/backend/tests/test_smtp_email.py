"""Email codes by Gmail SMTP, with Infobip still sending the SMS. No network."""

import smtplib
from unittest.mock import MagicMock

import pytest
from farmable_backend.auth import AuthError, Channel
from farmable_backend.infobip import InfobipOtpProvider, create_infobip_provider
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.smtp_email import MAX_ATTEMPTS, SmtpEmailSender

APP_PASSWORD = "abcdefghijklmnop"  # noqa: S105 - synthetic test credential
LIVE = {
    "environment": "staging",
    "integrations_mode": "live",
    "infobip_base_url": "abc123.api.infobip.com",
    "infobip_api_key": "test-key",
    "infobip_sms_sender": "Almanac",
    "smtp_user": "almanac.codes@gmail.com",
    "smtp_password": APP_PASSWORD,
    "email_from_address": "almanac.codes@gmail.com",
}


def sender(**overrides) -> SmtpEmailSender:
    values = {
        "host": "smtp.gmail.com",
        "port": 587,
        "tls_mode": "starttls",
        "user": "almanac.codes@gmail.com",
        "password": APP_PASSWORD,
        "from_name": "Almanac",
        "from_address": "almanac.codes@gmail.com",
        "sleep": lambda _: None,
    }
    return SmtpEmailSender(**(values | overrides))


def smtp(monkeypatch, name="SMTP"):
    connection = MagicMock()
    connection.__enter__.return_value = connection
    connection.__exit__.return_value = False
    factory = MagicMock(return_value=connection)
    monkeypatch.setattr(smtplib, name, factory)
    return factory, connection


def test_a_send_uses_starttls_and_the_app_password(monkeypatch):
    _factory, connection = smtp(monkeypatch)
    assert sender().send("farmer@example.com", "Subject", "<p>hi</p>", "hi") is True
    connection.starttls.assert_called_once()
    connection.login.assert_called_once_with("almanac.codes@gmail.com", APP_PASSWORD)
    envelope_from, envelope_to, body = connection.sendmail.call_args[0]
    assert (envelope_from, envelope_to) == ("almanac.codes@gmail.com", ["farmer@example.com"])
    assert "From: Almanac <almanac.codes@gmail.com>" in body


def test_ssl_mode_connects_with_smtp_ssl(monkeypatch):
    factory, connection = smtp(monkeypatch, "SMTP_SSL")
    assert sender(tls_mode="ssl", port=465).send("a@example.com", "S", "<p>h</p>", "h")
    factory.assert_called_once()
    connection.starttls.assert_not_called()


def test_a_header_injection_is_refused_without_connecting(monkeypatch):
    factory, _connection = smtp(monkeypatch)
    assert sender().send("a@example.com\r\nBcc: x@example.com", "S", "h", "h") is False
    factory.assert_not_called()


def test_a_bad_app_password_is_not_retried(monkeypatch):
    _factory, connection = smtp(monkeypatch)
    connection.login.side_effect = smtplib.SMTPAuthenticationError(535, b"bad")
    assert sender().send("a@example.com", "S", "h", "h") is False
    assert connection.login.call_count == 1


def test_a_transient_failure_is_retried_then_given_up(monkeypatch):
    factory, _connection = smtp(monkeypatch)
    factory.side_effect = OSError("connection reset")
    assert sender().send("a@example.com", "S", "h", "h") is False
    assert factory.call_count == MAX_ATTEMPTS


def test_the_email_code_goes_by_smtp_and_the_sms_still_by_infobip():
    email = MagicMock()
    email.send.return_value = True
    client = MagicMock()
    provider = InfobipOtpProvider(
        "abc123.api.infobip.com", "test-key", "Almanac", email=email, client=client
    )
    provider.deliver(Channel.EMAIL, "farmer@example.com", "123456")
    to, subject, html, text = email.send.call_args[0]
    assert to == "farmer@example.com"
    assert "123456" in text and "123456" in html
    client.send.assert_not_called()

    client.send.return_value = MagicMock(status_code=200)
    provider.deliver(Channel.PHONE, "+27821234567", "123456")
    assert client.send.call_count == 1


def test_a_failed_smtp_send_is_a_fixed_provider_error():
    email = MagicMock()
    email.send.return_value = False
    provider = InfobipOtpProvider(
        "abc123.api.infobip.com", "test-key", "Almanac", email=email, client=MagicMock()
    )
    with pytest.raises(AuthError, match="provider_error") as raised:
        provider.deliver(Channel.EMAIL, "farmer@example.com", "123456")
    assert raised.value.status_code == 503


def test_smtp_needs_only_user_password_and_from_address():
    settings = ServiceSettings(**LIVE)
    assert (settings.smtp_host, settings.smtp_port, settings.smtp_tls_mode) == (
        "smtp.gmail.com",
        587,
        "starttls",
    )
    assert settings.email_from_name == "Almanac"
    provider = create_infobip_provider(settings)
    assert provider is not None and isinstance(provider.email, SmtpEmailSender)
    provider.close()


def test_smtp_is_preferred_over_infobip_email_when_both_are_set():
    provider = create_infobip_provider(
        ServiceSettings(**LIVE, infobip_email_sender="codes@example.com")
    )
    assert provider is not None and isinstance(provider.email, SmtpEmailSender)
    provider.close()


@pytest.mark.parametrize("missing", ["smtp_user", "smtp_password", "email_from_address"])
def test_without_a_complete_email_route_sign_up_stays_off(missing):
    values = {key: value for key, value in LIVE.items() if key != missing}
    assert create_infobip_provider(ServiceSettings(**values)) is None


def test_the_app_password_is_accepted_as_google_shows_it():
    settings = ServiceSettings(**(LIVE | {"smtp_password": "abcd efgh ijkl mnop"}))
    assert settings.smtp_password is not None
    assert settings.smtp_password.get_secret_value() == APP_PASSWORD
