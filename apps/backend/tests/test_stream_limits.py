import asyncio
import json
import weakref
from collections.abc import AsyncIterator

import httpx
import pytest
from farmable_backend.integrations.base import SSE_MAX_EVENTS, ServiceResult
from farmable_backend.integrations.gemini import Gemini
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.integrations.smoke import stream_summary
from farmable_backend.main import create_app


class BytesStream(httpx.AsyncByteStream):
    def __init__(self, chunks: list[bytes]):
        self.chunks = chunks
        self.closed = False

    async def __aiter__(self) -> AsyncIterator[bytes]:
        for chunk in self.chunks:
            yield chunk

    async def aclose(self) -> None:
        self.closed = True


def payload(text: str) -> dict:
    return {"candidates": [{"content": {"parts": [{"text": text}]}}]}


def encoded(text: str) -> bytes:
    return ("data: " + json.dumps(payload(text), ensure_ascii=False) + "\n\n").encode()


@pytest.mark.parametrize(
    "chunks",
    [
        [encoded("x" * (512 * 1024))] * 12,
        [encoded("small")] * (SSE_MAX_EVENTS + 1),
        [b":" + b"x" * (1024 * 1024 + 1)],
        [b": keepalive\n"] * 180000,
        [encoded("\u00e9" * (600 * 1024))],
    ],
    ids=["total-bytes", "events", "unterminated-comment", "comments", "utf8-bytes"],
)
def test_stream_limits_fail_closed_without_retry(chunks):
    async def run():
        stream = BytesStream(chunks)
        calls = []

        def handler(request):
            calls.append(request)
            return httpx.Response(200, stream=stream)

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            adapter = Gemini(
                "gemini", client, ServiceSettings(environment="ci", integrations_mode="fake")
            )
            events = [event async for event in adapter.generate_stream({})]
            assert events[-1].done and not events[-1].ok
            assert events[-1].error == "invalid_response"
            assert len(events) <= SSE_MAX_EVENTS + 1
            assert len(calls) == 1 and stream.closed

    asyncio.run(run())


@pytest.mark.parametrize("ending", [b"\n", b"\r", b"\r\n"])
def test_line_endings_utf8_and_eof_across_transport_chunks(ending):
    async def run():
        raw = encoded("\u00e9").removesuffix(b"\n\n") + ending + ending
        raw += encoded("last").removesuffix(b"\n\n")
        stream = BytesStream([raw[index : index + 1] for index in range(len(raw))])
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, stream=stream))
        ) as client:
            adapter = Gemini(
                "gemini", client, ServiceSettings(environment="ci", integrations_mode="fake")
            )
            events = [event async for event in adapter.generate_stream({})]
            assert [event.data for event in events[:-1]] == [payload("\u00e9"), payload("last")]
            assert events[-1].done and events[-1].ok and stream.closed

    asyncio.run(run())


def test_smoke_summary_does_not_retain_stream_payloads():
    async def run():
        references = []

        async def source():
            for _ in range(1000):
                event = ServiceResult("gemini", True, data=payload("hello"))
                references.append(weakref.ref(event))
                assert sum(ref() is not None for ref in references) <= 2
                yield event
            yield ServiceResult("gemini", True, done=True)

        assert await stream_summary(source()) == (True, "contract")
        assert all(ref() is None for ref in references)

    asyncio.run(run())


@pytest.mark.parametrize(
    "terminal", [None, ServiceResult("gemini", False, error="timeout", done=True)]
)
def test_smoke_summary_requires_successful_terminal_event(terminal):
    async def source():
        yield ServiceResult("gemini", True, data=payload("hello"))
        if terminal:
            yield terminal

    assert not asyncio.run(stream_summary(source()))[0]


def test_database_constructor_failure_closes_service_registry(settings, monkeypatch):
    registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
    monkeypatch.setattr("farmable_backend.main.ServiceRegistry", lambda _: registry)

    def fail_database(_):
        raise RuntimeError("synthetic startup failure")

    monkeypatch.setattr("farmable_backend.main.Database", fail_database)

    async def run():
        app = create_app(settings)
        with pytest.raises(RuntimeError, match="synthetic startup failure"):
            async with app.router.lifespan_context(app):
                pytest.fail("Startup must not succeed")
        assert registry.client.is_closed

    asyncio.run(run())
