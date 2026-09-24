"""GmailSmtpEmailSender: retries transient failures, never retries permanent ones, no network."""

import smtplib
from unittest.mock import MagicMock

import pytest
from farmable_backend.integrations.email.base import DeliveryUnknown
from farmable_backend.integrations.email.gmail_smtp import MAX_ATTEMPTS, GmailSmtpEmailSender
from farmable_backend.integrations.settings import ServiceSettings
from pydantic import SecretStr


def make_settings(**overrides) -> ServiceSettings:
    defaults = {
        "environment": "staging",
        "integrations_mode": "live",
        "smtp_host": "smtp.gmail.com",
        "smtp_port": 587,
        "smtp_tls_mode": "starttls",
        "smtp_user": "noreply.almanac@gmail.com",
        "smtp_password": SecretStr("app-password-fixture"),
        "email_from_name": "Almanac",
        "email_from_address": "noreply.almanac@gmail.com",
    }
    defaults.update(overrides)
    return ServiceSettings(**defaults)


def test_missing_configuration_fails_fast():
    with pytest.raises(RuntimeError, match="SMTP_HOST"):
        GmailSmtpEmailSender(make_settings(smtp_host=None))


def test_successful_send_uses_starttls_and_returns_true(monkeypatch):
    connection = MagicMock()
    connection.__enter__.return_value = connection
    connection.__exit__.return_value = False
    smtp_cls = MagicMock(return_value=connection)
    monkeypatch.setattr(smtplib, "SMTP", smtp_cls)

    sender = GmailSmtpEmailSender(make_settings(), sleep=lambda _: None)
    assert sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi") is True

    connection.starttls.assert_called_once()
    connection.login.assert_called_once_with("noreply.almanac@gmail.com", "app-password-fixture")
    connection.sendmail.assert_called_once()
    to_envelope = connection.sendmail.call_args[0][1]
    assert to_envelope == ["farmer@example.test"]


def test_ssl_mode_uses_smtp_ssl(monkeypatch):
    connection = MagicMock()
    connection.__enter__.return_value = connection
    connection.__exit__.return_value = False
    smtp_ssl_cls = MagicMock(return_value=connection)
    monkeypatch.setattr(smtplib, "SMTP_SSL", smtp_ssl_cls)

    sender = GmailSmtpEmailSender(make_settings(smtp_tls_mode="ssl", smtp_port=465))
    assert sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi") is True
    smtp_ssl_cls.assert_called_once()
    connection.starttls.assert_not_called()


def test_auth_failure_never_retries(monkeypatch):
    smtp_cls = MagicMock(side_effect=smtplib.SMTPAuthenticationError(535, b"bad creds"))
    monkeypatch.setattr(smtplib, "SMTP", smtp_cls)

    sender = GmailSmtpEmailSender(make_settings(), sleep=lambda _: None)
    assert sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi") is False
    assert smtp_cls.call_count == 1


def test_permanent_smtp_error_never_retries(monkeypatch):
    error = smtplib.SMTPResponseException(550, b"mailbox unavailable")
    smtp_cls = MagicMock(side_effect=error)
    monkeypatch.setattr(smtplib, "SMTP", smtp_cls)

    sender = GmailSmtpEmailSender(make_settings(), sleep=lambda _: None)
    assert sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi") is False
    assert smtp_cls.call_count == 1


def test_transient_error_retries_up_to_max_attempts(monkeypatch):
    error = smtplib.SMTPResponseException(421, b"service not available")
    smtp_cls = MagicMock(side_effect=error)
    monkeypatch.setattr(smtplib, "SMTP", smtp_cls)
    sleeps: list[float] = []

    sender = GmailSmtpEmailSender(make_settings(), sleep=sleeps.append)
    assert sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi") is False
    assert smtp_cls.call_count == MAX_ATTEMPTS
    assert len(sleeps) == MAX_ATTEMPTS - 1


def test_control_characters_in_to_or_subject_are_refused(monkeypatch):
    smtp_cls = MagicMock()
    monkeypatch.setattr(smtplib, "SMTP", smtp_cls)

    sender = GmailSmtpEmailSender(make_settings(), sleep=lambda _: None)
    injected_to = "a@example.test\r\nBcc: evil@example.test"
    injected_subject = "Subject\r\nBcc: evil@example.test"
    assert sender.send(injected_to, "Subject", "<p>hi</p>", "hi") is False
    assert sender.send("a@example.test", injected_subject, "<p>hi</p>", "hi") is False
    smtp_cls.assert_not_called()


def test_network_error_retries_then_succeeds(monkeypatch):
    good_connection = MagicMock()
    good_connection.__enter__.return_value = good_connection
    good_connection.__exit__.return_value = False
    smtp_cls = MagicMock(side_effect=[OSError("network unreachable"), good_connection])
    monkeypatch.setattr(smtplib, "SMTP", smtp_cls)

    sender = GmailSmtpEmailSender(make_settings(), sleep=lambda _: None)
    assert sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi") is True
    assert smtp_cls.call_count == 2


@pytest.mark.parametrize("cleanup_error", [OSError("quit failed"), TimeoutError("quit timeout")])
def test_cleanup_failure_after_send_does_not_repeat_accepted_message(monkeypatch, cleanup_error):
    connection = MagicMock()
    connection.sendmail.return_value = {}
    connection.quit.side_effect = cleanup_error
    monkeypatch.setattr(smtplib, "SMTP", MagicMock(return_value=connection))

    sender = GmailSmtpEmailSender(make_settings(), sleep=lambda _: None)
    assert sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi") is True
    connection.sendmail.assert_called_once()


def test_submission_failure_is_ambiguous_and_not_retried(monkeypatch):
    connection = MagicMock()
    connection.sendmail.side_effect = OSError("response lost")
    monkeypatch.setattr(smtplib, "SMTP", MagicMock(return_value=connection))

    sender = GmailSmtpEmailSender(make_settings(), sleep=lambda _: None)
    with pytest.raises(DeliveryUnknown):
        sender.send("farmer@example.test", "Subject", "<p>hi</p>", "hi")
    connection.sendmail.assert_called_once()
