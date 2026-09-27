"""Email by SMTP (Gmail by default). Never logs recipients, subjects, bodies or codes.

Ported from Tshego's Gmail SMTP sender (727b781), which was verified against a real
account. Each send opens its own connection: smtplib.SMTP is not safe to share
between the auth pool's threads, and OTP volume does not justify a per-thread pool.
"""

import logging
import smtplib
import ssl
import time
from collections.abc import Callable
from email.mime.multipart import MIMEMultipart
from email.mime.text import MIMEText
from email.utils import formataddr
from typing import Literal

logger = logging.getLogger(__name__)

MAX_ATTEMPTS = 3
BACKOFF_BASE_SECONDS = 0.5
CONNECT_TIMEOUT_SECONDS = 10


class SmtpEmailSender:
    def __init__(
        self,
        *,
        host: str,
        port: int,
        tls_mode: Literal["starttls", "ssl"],
        user: str,
        password: str,
        from_name: str,
        from_address: str,
        sleep: Callable[[float], None] = time.sleep,
    ):
        self._host = host
        self._port = port
        self._tls_mode = tls_mode
        self._user = user
        self._password = password
        self._from = formataddr((from_name, from_address))
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
        # A CR/LF in a header value could inject extra headers, e.g. a forged Bcc.
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
                return True
            except smtplib.SMTPAuthenticationError:
                logger.critical(
                    "SMTP authentication failed - check the app password, and the Gmail "
                    "inbox for a security alert about a sign-in from a new server"
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
