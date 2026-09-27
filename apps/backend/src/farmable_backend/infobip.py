"""Verification codes by Infobip SMS and email (#7).

Synchronous on purpose: AuthService runs in the bounded auth thread pool and calls
`deliver` inside its transaction. Never logs, returns or raises a code, key or
provider response body. A failure is the fixed `provider_error`, or
`delivery_unknown` when the request may already have reached Infobip.
"""

import secrets

import httpx

from farmable_backend.auth import OTP_TTL, AuthError, Channel
from farmable_backend.integrations.settings import ServiceSettings

SMS_PATH = "/sms/2/text/advanced"
EMAIL_PATH = "/email/3/send"
SUBJECT = "Your Almanac verification code"
NOTICE_SUBJECT = "Almanac sign-up attempt"


class InfobipOtpProvider:
    def __init__(
        self,
        base_url: str,
        api_key: str,
        sms_sender: str,
        email_sender: str,
        *,
        client: httpx.Client | None = None,
    ):
        self.base = f"https://{base_url}"
        self.headers = {"Authorization": f"App {api_key}", "Accept": "application/json"}
        self.sms_sender = sms_sender
        self.email_sender = email_sender
        self.client = client or httpx.Client(timeout=10.0, follow_redirects=False, trust_env=False)

    def create_code(self, channel: Channel) -> str:
        return f"{secrets.randbelow(1_000_000):06d}"

    def deliver(self, channel: Channel, destination: str, code: str) -> None:
        minutes = int(OTP_TTL.total_seconds() // 60)
        text = f"Your Almanac verification code is {code}. It expires in {minutes} minutes."
        self._send(channel, destination, SUBJECT, text)

    def notify_existing_account(self, channel: Channel, destination: str) -> None:
        # Sign-up and contact changes answer an existing email/phone exactly as
        # they answer a new one (#9 enumeration resistance); the real owner is
        # warned here instead.
        noun = "phone number" if channel is Channel.PHONE else "email address"
        text = (
            f"Someone tried to use this {noun} for an Almanac account. "
            "If this wasn't you, no action is needed."
        )
        self._send(channel, destination, NOTICE_SUBJECT, text)

    def _send(self, channel: Channel, destination: str, subject: str, text: str) -> None:
        if channel is Channel.PHONE:
            request = self.client.build_request(
                "POST",
                self.base + SMS_PATH,
                headers=self.headers,
                json={
                    "messages": [
                        {
                            # Signup only accepts +E.164; Infobip wants the digits alone.
                            "destinations": [{"to": destination.removeprefix("+")}],
                            "from": self.sms_sender,
                            "text": text,
                        }
                    ]
                },
            )
        else:
            request = self.client.build_request(
                "POST",
                self.base + EMAIL_PATH,
                headers=self.headers,
                # Infobip's email API is multipart form fields, not JSON.
                files=[
                    ("from", (None, self.email_sender)),
                    ("to", (None, destination)),
                    ("subject", (None, subject)),
                    ("text", (None, text)),
                ],
            )
        try:
            response = self.client.send(request)
        except (httpx.ConnectError, httpx.ConnectTimeout, httpx.PoolTimeout):
            raise AuthError("provider_error", 503) from None  # Never reached Infobip.
        except (httpx.TimeoutException, httpx.ReadError, httpx.RemoteProtocolError):
            # The request may have been dispatched. AuthService keeps the code so
            # a retry with the same Idempotency-Key never pays for a second SMS.
            raise AuthError("delivery_unknown", 503) from None
        except httpx.HTTPError:
            raise AuthError("provider_error", 503) from None
        if not 200 <= response.status_code < 300:
            raise AuthError("provider_error", 503)

    def close(self) -> None:
        self.client.close()


def create_infobip_provider(settings: ServiceSettings) -> InfobipOtpProvider | None:
    """Infobip for live integrations with every value present, otherwise None.

    None leaves AuthService on its fail-closed DisabledOtpProvider, so a half-set
    configuration refuses to send rather than sending from the wrong sender.
    """
    key = settings.infobip_api_key.get_secret_value() if settings.infobip_api_key else ""
    if not (
        settings.integrations_mode == "live"
        and settings.infobip_base_url
        and key
        and settings.infobip_sms_sender
        and settings.infobip_email_sender
    ):
        return None
    return InfobipOtpProvider(
        settings.infobip_base_url, key, settings.infobip_sms_sender, settings.infobip_email_sender
    )
