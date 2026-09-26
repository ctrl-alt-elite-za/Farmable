"""Live sign-up codes through Twilio Verify: SMS for the phone, email for the address.

Twilio generates, delivers and checks the code, so the plaintext never reaches this
service. AuthService still owns expiry, attempt limits and send rate limits.
"""

import re
import secrets

import httpx

from farmable_backend.auth import AuthError, Channel
from farmable_backend.integrations.settings import ServiceSettings

_TWILIO_CHANNEL = {Channel.PHONE: "sms", Channel.EMAIL: "email"}
_CODE = re.compile(r"[0-9]{4,10}")


class TwilioVerifyOtpProvider:
    """An OtpProvider whose codes are owned by Twilio Verify, not by AuthService."""

    def __init__(
        self,
        account_sid: str,
        service_sid: str,
        auth_token: str,
        *,
        transport: httpx.BaseTransport | None = None,
    ):
        self._url = f"https://verify.twilio.com/v2/Services/{service_sid}"
        self._client = httpx.Client(
            auth=(account_sid, auth_token), timeout=10.0, transport=transport
        )

    def create_code(self, channel: Channel) -> str:
        # Twilio sends its own code. This value is only hashed into the challenge
        # row, so a locally stored hash can never be matched by a guess.
        return secrets.token_urlsafe(32)

    def deliver(self, channel: Channel, destination: str, code: str) -> None:
        self._post("Verifications", {"To": destination, "Channel": _TWILIO_CHANNEL[channel]})

    def check(self, channel: Channel, destination: str, code: str) -> bool:
        if not _CODE.fullmatch(code):
            return False
        response = self._post(
            "VerificationCheck", {"To": destination, "Code": code}, missing_ok=True
        )
        return response is not None and response.get("status") == "approved"

    def _post(self, action: str, data: dict[str, str], *, missing_ok: bool = False):
        try:
            response = self._client.post(f"{self._url}/{action}", data=data)
        except httpx.HTTPError:
            raise AuthError("provider_unavailable", 503) from None
        # 404: no pending verification (expired, or already approved) - a wrong code.
        if missing_ok and response.status_code == 404:
            return None
        if response.status_code == 429:
            raise AuthError("otp_rate_limited", 429)
        if response.status_code >= 400:
            raise AuthError("provider_error", 503)
        try:
            return response.json()
        except ValueError:
            raise AuthError("provider_error", 503) from None

    def close(self) -> None:
        self._client.close()


def create_live_otp_provider(settings: ServiceSettings) -> TwilioVerifyOtpProvider | None:
    """Twilio Verify when live and fully configured; otherwise None (sign-up fails closed)."""
    token = settings.twilio_auth_token
    if (
        settings.integrations_mode != "live"
        or not settings.twilio_account_sid
        or not settings.twilio_verify_service_sid
        or token is None
        or not settings.twilio_fraud_guard_confirmed
    ):
        return None
    return TwilioVerifyOtpProvider(
        settings.twilio_account_sid,
        settings.twilio_verify_service_sid,
        token.get_secret_value(),
    )
