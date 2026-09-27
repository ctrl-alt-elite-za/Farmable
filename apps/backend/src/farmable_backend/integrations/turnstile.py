from uuid import uuid4

import httpx

from .base import Adapter, ServiceResult


class Turnstile(Adapter):
    async def validate(self, token: str, action: str = "sign_up") -> ServiceResult:
        if not token or len(token) > 2048 or not action or len(action) > 32:
            return self.failure("invalid_input")
        secret = self.secret(self.settings.turnstile_secret)
        hostname = (
            "farmable.test"
            if self.settings.integrations_mode == "fake"
            else self.settings.turnstile_hostname
        )
        if not secret or not hostname:
            return self.failure("misconfigured")
        result = await self.call(
            httpx.Request(
                "POST",
                "https://challenges.cloudflare.com/turnstile/v0/siteverify",
                json={
                    "secret": secret,
                    "response": token,
                    "idempotency_key": str(uuid4()),
                    "action": action,
                },
            )
        )
        if result.ok:
            data = result.data or {}
            if (
                data.get("success") is not True
                or data.get("hostname") != hostname
                or data.get("action") != action
            ):
                return self.failure("rejected", result.status)
        return result
