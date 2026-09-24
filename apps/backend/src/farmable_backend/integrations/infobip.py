import re
from uuid import uuid4

import httpx

from .base import Adapter, ServiceResult

_FAKE_BASE_URL = "fake.infobip.test"
_ACCEPTED_SMS_STATUSES = frozenset({"MESSAGE_ACCEPTED", "PENDING_ACCEPTED"})


def _normalized_destination(value: str) -> str:
    return re.sub(r"\D", "", value)


def _validated_sms_result(result: ServiceResult, destination: str) -> ServiceResult:
    if not result.ok:
        return result
    messages = (result.data or {}).get("messages")
    if not isinstance(messages, list) or len(messages) != 1:
        return ServiceResult(result.service, False, error="invalid_response", status=result.status)
    message = messages[0]
    if not isinstance(message, dict):
        return ServiceResult(result.service, False, error="invalid_response", status=result.status)
    status = message.get("status")
    message_id = message.get("messageId")
    if (
        not isinstance(message.get("to"), str)
        or _normalized_destination(message["to"]) != _normalized_destination(destination)
        or not isinstance(message_id, str)
        or not message_id
        or not isinstance(status, dict)
        or status.get("name") not in _ACCEPTED_SMS_STATUSES
    ):
        return ServiceResult(result.service, False, error="invalid_response", status=result.status)
    return result


class Infobip(Adapter):
    """SMS and WhatsApp template delivery. Never logs message bodies, destinations, or codes.

    Email delivery uses ``integrations/email`` (Gmail SMTP) instead.

    WhatsApp template messages require a WhatsApp Business Account (WABA)
    sender registered with Infobip/Meta. There is no default sender: set
    ``INFOBIP_WHATSAPP_SENDER``. Infobip's shared sandbox sender
    (``447860088970``) works for testing but is Infobip's own number - it
    cannot carry custom branding. Real "Almanac"-branded WhatsApp messages
    need a dedicated, Meta-verified WABA number, which is an account
    provisioning step outside this codebase, not a config value.
    """

    def _base_url(self) -> str | None:
        if self.settings.integrations_mode == "fake":
            return _FAKE_BASE_URL
        return self.settings.infobip_base_url

    async def send_sms(self, destination: str, text: str) -> ServiceResult:
        base_url = self._base_url()
        api_key = self.secret(self.settings.infobip_api_key)
        sender = (
            "InfoSMS"
            if self.settings.integrations_mode == "fake"
            else self.settings.infobip_sms_sender
        )
        if not base_url or not api_key:
            return self.failure("misconfigured")
        message: dict[str, object] = {
            "destinations": [{"to": destination}],
            "content": {"text": text},
        }
        if sender:
            message["sender"] = sender
        result = await self.call(
            httpx.Request(
                "POST",
                f"https://{base_url}/sms/3/messages",
                headers={"Authorization": f"App {api_key}"},
                json={"messages": [message]},
            ),
            # Infobip has no verified idempotency key for this endpoint. A
            # timeout after dispatch must not create duplicate billable SMS.
            retry=False,
        )
        return _validated_sms_result(result, destination)

    async def send_whatsapp_template(
        self,
        destination: str,
        template_name: str,
        placeholders: list[str],
        *,
        language: str = "en",
    ) -> ServiceResult:
        base_url = self._base_url()
        api_key = self.secret(self.settings.infobip_api_key)
        sender = (
            "10000000000"
            if self.settings.integrations_mode == "fake"
            else self.settings.infobip_whatsapp_sender
        )
        if not base_url or not api_key or not sender:
            return self.failure("misconfigured")
        return await self.call(
            httpx.Request(
                "POST",
                f"https://{base_url}/whatsapp/1/message/template",
                headers={"Authorization": f"App {api_key}"},
                json={
                    "messages": [
                        {
                            "from": sender,
                            "to": destination,
                            "messageId": str(uuid4()),
                            "content": {
                                "templateName": template_name,
                                "templateData": {"body": {"placeholders": placeholders}},
                                "language": language,
                            },
                        }
                    ]
                },
            )
        )
