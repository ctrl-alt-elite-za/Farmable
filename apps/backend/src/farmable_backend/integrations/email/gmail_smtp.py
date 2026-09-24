"""Gmail SMTP email transport. Never logs recipients, subjects, or bodies.

Each ``send`` opens and closes its own SMTP connection rather than reusing
one across calls: ``smtplib.SMTP`` is not safe for concurrent use from
multiple threads, and the auth thread pool runs sends from more than one
worker thread at once. True reuse would need a per-thread connection pool,
which is more machinery than this OTP-volume workload needs.
"""

import logging
import smtplib
import ssl
import time
from collections.abc import Callable
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr

from farmable_backend.integrations.settings import ServiceSettings

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 3
BACKOFF_BASE_SECONDS = 0.5
CONNECT_TIMEOUT_SECONDS = 10


class GmailSmtpEmailSender:
    def __init__(self, settings: ServiceSettings, *, sleep: Callable[[float], None] = time.sleep):
        missing = [
            name
            for name, value in (
                ("SMTP_HOST", settings.smtp_host),
                ("SMTP_USER", settings.smtp_user),
                ("SMTP_PASSWORD", settings.smtp_password),
                ("EMAIL_FROM_NAME", settings.email_from_name),
                ("EMAIL_FROM_ADDRESS", settings.email_from_address),
            )
            if not value
        ]
        if missing:
            raise RuntimeError("Missing required email configuration: " + ", ".join(missing))
        self._host: str = settings.smtp_host  # type: ignore[assignment]
        self._port = settings.smtp_port
        self._tls_mode = settings.smtp_tls_mode
        self._user: str = settings.smtp_user  # type: ignore[assignment]
        self._password = settings.smtp_password.get_secret_value()  # type: ignore[union-attr]
        self._from = formataddr((settings.email_from_name, settings.email_from_address))
        self._sleep = sleep

    def _connect(self) -> smtplib.SMTP:
        context = ssl.create_default_context()
        connection: smtplib.SMTP
        if self._tls_mode == "ssl":
            connection = smtplib.SMTP_SSL(
                self._host, self._port, timeout=CONNECT_TIMEOUT_SECONDS, context=context
            )
        else:
            connection = smtplib.SMTP(self._host, self._port, timeout=CONNECT_TIMEOUT_SECONDS)
            connection.starttls(context=context)
        connection.login(self._user, self._password)
        return connection

    def send(self, to: str, subject: str, html: str, text: str) -> bool:
        # Defense in depth: every current caller passes a fixed subject and a
        # pre-validated destination, but this is a general-purpose interface -
        # a header value with an embedded CR/LF could inject extra headers
        # (e.g. a forged Bcc) into the message.
        if "\r" in to or "\n" in to or "\r" in subject or "\n" in subject:
            logger.error("Refused an email send with a control character in to/subject")
            return False
        message = MIMEMultipart("alternative")
        message["Subject"] = subject
        message["From"] = self._from
        message["To"] = to
        message.attach(MIMEText(text, "plain"))
        message.attach(MIMEText(html, "html"))
        body = message.as_string()

        for attempt in range(MAX_ATTEMPTS):
            try:
                with self._connect() as connection:
                    connection.sendmail(self._user, [to], body)
                logger.info("Email send succeeded")
                return True
            except smtplib.SMTPAuthenticationError:
                logger.critical(
                    "SMTP authentication failed - Google may have blocked a login from a "
                    "new server IP; check the Gmail account inbox for a security alert"
                )
                return False
            except smtplib.SMTPResponseException as error:
                if 500 <= error.smtp_code < 600:
                    logger.error("Email send failed with a permanent SMTP error")
                    return False
                logger.warning("Email send failed with a transient SMTP error; retrying")
            except (smtplib.SMTPException, OSError, TimeoutError):
                logger.warning("Email send failed with a transient network error; retrying")
            if attempt < MAX_ATTEMPTS - 1:
                self._sleep(BACKOFF_BASE_SECONDS * 2**attempt)
        logger.error("Email send failed after exhausting retries")
        return False
