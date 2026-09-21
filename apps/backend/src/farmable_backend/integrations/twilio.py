import base64
import re

import httpx

from .base import Adapter, ServiceResult


class Twilio(Adapter):
    async def verify(self, phone: str, code: str | None = None) -> ServiceResult:
        if not re.fullmatch(r"\+[1-9][0-9]{7,14}", phone) or (
            code is not None and not re.fullmatch(r"[0-9]{4,10}", code)
        ):
            return self.failure("invalid_input")
        fake = self.settings.integrations_mode == "fake"
        account = "AC" + "0" * 32 if fake else self.settings.twilio_account_sid
        service = "VA" + "0" * 32 if fake else self.settings.twilio_verify_service_sid
        token = self.secret(self.settings.twilio_auth_token)
        if (
            not account
            or not service
            or not token
            or not (fake or self.settings.twilio_fraud_guard_confirmed)
        ):
            return self.failure("misconfigured")
        authorization = base64.b64encode(f"{account}:{token}".encode()).decode()
        action = "Verifications" if code is None else "VerificationCheck"
        body = {"To": phone, "Channel": "sms"} if code is None else {"To": phone, "Code": code}
        return await self.call(
            httpx.Request(
                "POST",
                f"https://verify.twilio.com/v2/Services/{service}/{action}",
                headers={"Authorization": "Basic " + authorization},
                data=body,
            )
        )
