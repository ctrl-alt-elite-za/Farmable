"""Fixed-age expiry applies even while the physical cleanup worker is offline."""

import asyncio
import json
from datetime import UTC, datetime, timedelta
from uuid import uuid4

import pytest
from farmable_backend.account import AccountService
from farmable_backend.assistant import retention
from farmable_backend.assistant.privacy import NOTICE_VERSION, ConsentGrant
from farmable_backend.assistant.schemas import ConversationCreate, TurnCreate
from farmable_backend.models import AssistantBudget, AssistantConsent, AssistantTurn, SavedPlan
from farmable_backend.record_access import ApiError, utc
from sqlalchemy import select
from test_assistant import assistant as assistant_fixture
from test_assistant import post, script, wire

assistant = assistant_fixture


def old_turn(assistant, *, age=31, status="completed", conversation=None, owner=None):
    now = datetime.now(UTC)
    record = AssistantTurn(
        id=uuid4(),
        conversation_id=conversation or assistant.conversation,
        owner_id=owner or assistant.alice.owner,
        created_at=now - timedelta(days=age),
        deadline=now - timedelta(days=age) + timedelta(seconds=90),
        message="expired private message",
        reply="expired private reply",
        tools=[{"result": "expired private tool data"}],
        usage=[{"totalTokenCount": 10}],
        status=status,
        model="fixture-model",
        policy="fixture",
        reserved_micro_usd=10,
    )
    with assistant.sessions.begin() as session:
        session.add(record)
    return record.id


@pytest.mark.parametrize("status", ["completed", "interrupted", "failed", "running"])
def test_fixed_boundary_erases_content_but_preserves_usage_and_plans(
    assistant, monkeypatch, status
):
    identifier = old_turn(assistant, status=status)
    recent = old_turn(assistant, age=29)
    plan_id = uuid4()
    with assistant.sessions.begin() as session:
        record = session.get(AssistantTurn, identifier)
        created = utc(record.created_at)
        boundary = created + timedelta(days=30)
        session.add(
            SavedPlan(
                id=plan_id,
                owner_id=assistant.alice.owner,
                farm_id=assistant.alice.farm,
                section_id=assistant.alice.section,
                status="approved",
                plan={"crop": "cabbage"},
                approved_at=created,
                created_at=created,
            )
        )
    monkeypatch.setattr(retention, "db_now", lambda _: boundary - timedelta(microseconds=1))
    assert retention.purge_batch(assistant.sessions) == 0
    monkeypatch.setattr(retention, "db_now", lambda _: boundary)
    assert retention.purge_batch(assistant.sessions) == 1
    assert retention.purge_batch(assistant.sessions) == 0
    with assistant.sessions() as session:
        record = session.get(AssistantTurn, identifier)
        assert (record.message, record.reply, record.tools) == ("", "", [])
        assert utc(record.content_deleted_at) == boundary and utc(record.created_at) == created
        assert record.usage == [{"totalTokenCount": 10}] and record.reserved_micro_usd == 10
        assert record.status == ("failed" if status == "running" else status)
        if status == "running":
            assert record.error == "assistant_history_expired"
        assert session.get(AssistantTurn, recent).message == "expired private message"
        plan = session.get(SavedPlan, plan_id)
        assert plan.plan == {"crop": "cabbage"} and plan.status == "approved"
        assert plan.deleted_at is None


def test_expired_history_export_and_provider_context_hidden_without_cleanup(assistant):
    identifier = old_turn(assistant)
    requests = script(assistant, [[wire([{"text": "New reply"}])]])
    response, _, recent = post(assistant, message="New question")
    assert response.status_code == 200
    history = assistant.store.history(assistant.alice.auth, assistant.conversation)
    assert [turn.id for turn in history.turns] == [recent]
    account = AccountService(assistant.sessions, export_token_secret="unit-export-token-secret")
    account.set_consent(assistant.alice.auth, "data_export", "1", True)
    exported = account.export_document(assistant.alice.auth)
    assert [turn["id"] for turn in exported["assistant_turns"]] == [str(recent)]
    assert "expired private" not in json.dumps(requests) + json.dumps(exported)
    # The above must be true even if cleanup has never run.
    with assistant.sessions() as session:
        assert session.get(AssistantTurn, identifier).content_deleted_at is None


def test_replay_cannot_restore_or_rebill_erased_turn_and_remains_owner_scoped(assistant):
    identifier = old_turn(assistant, status="running")
    requests = script(assistant, [])
    snapshot = assistant.store.get(assistant.alice.auth, assistant.conversation, identifier)
    assert snapshot.content_deleted_at is not None and snapshot.message == ""
    response, events, _ = post(assistant, message="different message", identifier=identifier)
    assert response.status_code == 200 and requests == []
    assert events[0]["data"]["replayed"] is True
    assert "expired private" not in response.text
    updated = assistant.store.update(
        assistant.alice.auth,
        assistant.conversation,
        identifier,
        reply="late content",
        tools=[{"result": "late"}],
        status="completed",
    )
    assert updated.reply == "" and updated.tools == [] and updated.status == "failed"
    with pytest.raises(ApiError) as error:
        assistant.store.get(assistant.bob.auth, assistant.conversation, identifier)
    assert error.value.status == 404
    with assistant.sessions() as session:
        assert session.get(AssistantBudget, 1).reserved_micro_usd == 0


def test_reopening_and_regranting_never_extend_retention(assistant):
    identifier = old_turn(assistant)
    with assistant.sessions() as session:
        created = session.get(AssistantTurn, identifier).created_at
    assistant.store.create(
        assistant.alice.auth,
        ConversationCreate(
            id=assistant.conversation,
            farm_id=assistant.alice.farm,
        ),
    )
    assistant.store.consent(assistant.alice.auth, assistant.conversation, withdraw=True)
    assistant.store.consent(
        assistant.alice.auth,
        assistant.conversation,
        ConsentGrant(
            notice_version=NOTICE_VERSION,
            model="fixture-model",
        ),
    )
    assistant.store.admit(
        assistant.alice.auth,
        assistant.conversation,
        TurnCreate(
            id=uuid4(),
            message="A new message",
        ),
    )
    assert retention.purge_batch(assistant.sessions) == 1
    with assistant.sessions() as session:
        assert session.get(AssistantTurn, identifier).created_at == created


def test_cleanup_is_bounded_and_covers_all_owners(assistant, monkeypatch):
    monkeypatch.setattr(retention, "BATCH_SIZE", 2)
    other = assistant.store.create(
        assistant.bob.auth,
        ConversationCreate(
            id=uuid4(),
            farm_id=assistant.bob.farm,
        ),
    )
    old_turn(assistant)
    old_turn(assistant)
    old_turn(assistant, conversation=other.id, owner=assistant.bob.owner)
    assert retention.purge_batch(assistant.sessions) == 2
    assert retention.purge_batch(assistant.sessions) == 1
    assert retention.purge_batch(assistant.sessions) == 0
    with assistant.sessions() as session:
        assert all(t.content_deleted_at is not None for t in session.scalars(select(AssistantTurn)))


@pytest.mark.parametrize("version", ["gemini-conversation-v1", "gemini-conversation-v2"])
def test_previous_notice_requires_explicit_reconsent(assistant, version):
    with assistant.sessions.begin() as session:
        session.get(AssistantConsent, assistant.conversation).notice_version = version
    requests = script(assistant, [])
    response, _, _ = post(assistant)
    assert response.status_code == 403 and requests == []


@pytest.mark.parametrize("fails", [False, True])
def test_worker_runs_cleanup_and_stops_without_logging_content(monkeypatch, caplog, fails):
    worker = retention.RetentionWorker(None)
    calls = []

    async def run():
        loop = asyncio.get_running_loop()

        def cleanup(sessions):
            calls.append(sessions)
            loop.call_soon_threadsafe(worker.stop.set)
            if fails:
                raise RuntimeError("private database content must not be logged")
            return 0

        monkeypatch.setattr(retention, "purge_batch", cleanup)
        await asyncio.wait_for(worker.run(), timeout=2)

    asyncio.run(run())
    assert calls == [None]
    assert "private database content" not in caplog.text
    assert ("Assistant retention cleanup unavailable" in caplog.text) == fails
