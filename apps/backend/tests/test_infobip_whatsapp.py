"""send_whatsapp_template: a standalone capability, not wired into any app flow."""

import asyncio
import json

import httpx
from farmable_backend.integrations.infobip import Infobip
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings


def fake_settings(**kwargs) -> ServiceSettings:
    return ServiceSettings(environment="ci", integrations_mode="fake", **kwargs)


def test_send_whatsapp_template_request_shape():
    async def run():
        registry = ServiceRegistry(fake_settings())
        captured = []
        original = registry.transport.handle_async_request

        async def capture(request):
            captured.append(request)
            return await original(request)

        registry.transport.handle_async_request = capture
        try:
            result = await registry.infobip.send_whatsapp_template(
                "27724992855", "test_whatsapp_template_en", ["Tshegofatso"]
            )
            assert result.ok
            request = captured[-1]
            assert request.url.path == "/whatsapp/1/message/template"
            assert request.headers["authorization"] == "App fixture-key"
            body = json.loads(request.content)
            message = body["messages"][0]
            assert message["to"] == "27724992855"
            assert message["content"]["templateName"] == "test_whatsapp_template_en"
            assert message["content"]["templateData"]["body"]["placeholders"] == ["Tshegofatso"]
            assert message["content"]["language"] == "en"
            assert message["messageId"]
        finally:
            await registry.close()

    asyncio.run(run())


def test_send_whatsapp_template_without_sender_is_misconfigured():
    # Live mode has no hardcoded default sender (unlike fake mode); a missing
    # INFOBIP_WHATSAPP_SENDER must fail closed without ever calling out.
    async def refuse_all_requests(request: httpx.Request) -> httpx.Response:
        raise AssertionError("No network call should happen when misconfigured")

    async def run():
        settings = ServiceSettings(
            environment="staging",
            integrations_mode="live",
            infobip_base_url="example.test",
            infobip_api_key="fixture-key",  # noqa: S106 - deliberately synthetic
            infobip_whatsapp_sender=None,
        )
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(refuse_all_requests)
        ) as client:
            adapter = Infobip("infobip", client, settings)
            result = await adapter.send_whatsapp_template(
                "27724992855", "test_whatsapp_template_en", ["Tshegofatso"]
            )
        assert result.error == "misconfigured"

    asyncio.run(run())
