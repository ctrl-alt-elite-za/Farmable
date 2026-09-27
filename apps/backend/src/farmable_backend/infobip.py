"""Verification codes by Infobip SMS and email (#7).

Synchronous on purpose: AuthService runs in the bounded auth thread pool and calls
`deliver` inside its transaction. Never logs, returns or raises a code, key or
provider response body; every failure is the same fixed `provider_error`.
"""

import secrets

import httpx

from farmable_backend.auth import OTP_TTL, AuthError, Channel
from farmable_backend.integrations.settings import ServiceSettings

SMS_PATH = "/sms/2/text/advanced"
EMAIL_PATH = "/email/3/send"
SUBJECT = "Your Almanac verification code"


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
                    ("subject", (None, SUBJECT)),
                    ("text", (None, text)),
                ],
            )
        try:
            response = self.client.send(request)
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
