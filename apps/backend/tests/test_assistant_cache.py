"""Synthetic explicit-cache protocol, privacy and cost tests; no paid calls."""

import asyncio
import json
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from farmable_backend.integrations.base import ServiceResult
from farmable_backend.models import AssistantModelCall
from sqlalchemy import select
from test_assistant import assistant as assistant_fixture
from test_assistant import post, script, wire
from test_assistant_accounting import pricing, usage

assistant = assistant_fixture


def enable(assistant):
    assistant.store.policy.cache_enabled = True
    assistant.store.policy.text_pricing = pricing().model_copy(
        update={
            "cache_write_micro_usd_per_million": 1_000_000,
            "cache_storage_micro_usd_per_million_token_hours": 1_000_000,
        }
    )
    captured = []

    async def transport(request):
        captured.append(
            (
                request.method,
                str(request.url),
                json.loads(request.content) if request.content else {},
            )
        )
        if request.method == "DELETE":
            return httpx.Response(200, json={})
        return httpx.Response(
            200,
            json={
                "name": "cachedContents/test-cache",
                "model": "models/fixture-model",
                "usageMetadata": {"totalTokenCount": 100},
                "expireTime": (datetime.now(UTC) + timedelta(seconds=300)).isoformat(),
            },
        )

    client = httpx.AsyncClient(transport=httpx.MockTransport(transport))
    assistant.runtime.cache.adapter.client = client
    return captured, client


def rounds(count=2):
    return [
        [wire([{"text": "Hello"}], usageMetadata=usage(), modelVersion="fixture-version")]
        for _ in range(count)
    ]


def test_cache_reuses_static_context_not_farmer_history_and_prices_creation(assistant):
    captured, client = enable(assistant)
    requests = script(assistant, rounds())
    post(assistant, "PRIVATE FIRST MESSAGE")
    post(assistant, "PRIVATE SECOND MESSAGE")
    assert len(captured) == 1
    creation = captured[0][2]
    assert "contents" not in creation and "PRIVATE" not in json.dumps(creation)
    assert set(creation) == {"systemInstruction", "tools", "toolConfig", "model", "ttl"}
    assert all(request["cachedContent"] == "cachedContents/test-cache" for request in requests)
    assert all(
        "systemInstruction" not in request and "tools" not in request for request in requests
    )
    assert "PRIVATE SECOND MESSAGE" in json.dumps(requests[1]["contents"])
    with assistant.sessions() as session:
        calls = session.scalars(
            select(AssistantModelCall).order_by(AssistantModelCall.created_at)
        ).all()
        assert [(call.cache_mode, call.cache_cost_micro_usd) for call in calls] == [
            ("created", 109),
            ("reused", 0),
        ]
        assert [call.estimated_micro_usd for call in calls] == [221, 112]
    asyncio.run(assistant.runtime.cache.close())
    assert captured[-1][0] == "DELETE"
    asyncio.run(client.aclose())


@pytest.mark.parametrize("change", ["expiry", "instructions"])
def test_cache_invalidates_expiry_or_changed_static_context(assistant, monkeypatch, change):
    from farmable_backend.assistant import runtime

    captured, client = enable(assistant)
    script(assistant, rounds())
    post(assistant)
    if change == "expiry":
        assistant.runtime.cache.expires = 0
    else:
        monkeypatch.setattr(runtime, "SYSTEM", runtime.SYSTEM + " Updated static instruction.")
    post(assistant)
    assert [item[0] for item in captured] == ["POST", "DELETE", "POST"]
    asyncio.run(client.aclose())


@pytest.mark.parametrize("failure", ["minimum", "timeout", "malformed"])
def test_unavailable_cache_falls_back_without_retry_or_free_unknown_charge(assistant, failure):
    _, client = enable(assistant)
    seen = []

    async def call(request):
        seen.append(request)
        return {
            "minimum": ServiceResult("gemini", False, status=400, error="http"),
            "timeout": ServiceResult("gemini", False, error="timeout"),
            "malformed": ServiceResult("gemini", True, data={"name": "https://attacker.test/"}),
        }[failure]

    assistant.runtime.cache.adapter.call = call
    requests = script(assistant, rounds())
    assert post(assistant)[1][-1]["type"] == "done"
    post(assistant)
    assert len(seen) == 1  # Cooldown, no cache-creation retry on the next turn.
    assert all("cachedContent" not in request for request in requests)
    with assistant.sessions() as session:
        first = session.scalar(select(AssistantModelCall).order_by(AssistantModelCall.created_at))
        assert first.cache_mode == "unavailable"
        assert first.estimated_micro_usd == (112 if failure == "minimum" else None)
    asyncio.run(client.aclose())


def test_cache_without_reviewed_storage_rates_does_not_make_paid_creation(assistant):
    assistant.store.policy.cache_enabled = True
    assistant.store.policy.text_pricing = pricing()
    requests = script(assistant, rounds(1))
    assert post(assistant)[1][-1]["type"] == "done"
    assert "cachedContent" not in requests[0]


def test_withdrawal_during_cache_creation_never_sends_farmer_contents(assistant):
    captured, client = enable(assistant)
    original = assistant.runtime.cache.adapter.call

    async def withdrawn(request):
        result = await original(request)
        assistant.store.consent(assistant.alice.auth, assistant.conversation, withdraw=True)
        return result

    assistant.runtime.cache.adapter.call = withdrawn
    requests = script(assistant, [])
    assert post(assistant, "PRIVATE MESSAGE")[1][-1]["type"] == "interrupted"
    assert not requests and "PRIVATE MESSAGE" not in json.dumps(captured)
    with assistant.sessions() as session:
        row = session.scalar(select(AssistantModelCall))
        assert row.cache_cost_micro_usd == 109 and row.state == "started"
        # No completion callback: keep the reservation, never assume a free turn.
    asyncio.run(client.aclose())
