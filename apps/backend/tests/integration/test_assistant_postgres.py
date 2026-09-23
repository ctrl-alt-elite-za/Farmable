"""Real PostgreSQL locking: no double admission or global budget overspend."""

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Barrier
from uuid import uuid4

import pytest
from farmable_backend.assistant import retention
from farmable_backend.assistant.privacy import NOTICE_VERSION, ConsentGrant
from farmable_backend.assistant.retention import purge_batch
from farmable_backend.assistant.schemas import ConversationCreate, TurnCreate
from farmable_backend.assistant.settings import AssistantSettings
from farmable_backend.assistant.store import Store
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.models import AssistantBudget, AssistantTurn, User
from farmable_backend.record_access import ApiError
from sqlalchemy import delete, event, func, select
from sqlalchemy.orm import sessionmaker
from test_assistant import policy, seed

pytestmark = pytest.mark.integration


def test_retention_skips_locked_turns_and_fences_late_updates(monkeypatch):
    engine = make_engine(Settings())
    sessions = sessionmaker(engine, expire_on_commit=False)
    owner = seed(sessions)
    store = Store(sessions, policy(), ServiceSettings(environment="ci", integrations_mode="fake"))
    conversation = store.create(owner.auth, ConversationCreate(id=uuid4(), farm_id=owner.farm))
    identifier = uuid4()
    created = datetime.now(UTC)
    # Advance only this test's purger clock. The stack's live worker must not
    # race to erase the fixture before the locking assertions run.
    monkeypatch.setattr(retention, "db_now", lambda _: created + timedelta(days=31))
    try:
        with sessions.begin() as session:
            session.add(
                AssistantTurn(
                    id=identifier,
                    conversation_id=conversation.id,
                    owner_id=owner.owner,
                    created_at=created,
                    deadline=created + timedelta(seconds=90),
                    status="running",
                    message="private",
                    reply="partial",
                    tools=[{"result": "private"}],
                    usage=[],
                    model="fixture-model",
                    policy="fixture",
                    reserved_micro_usd=10,
                )
            )
        with sessions.begin() as locked:
            record = locked.scalar(
                select(AssistantTurn)
                .where(
                    AssistantTurn.id == identifier,
                )
                .with_for_update()
            )
            # A second connection must skip this row, not block or erase active writes.
            assert purge_batch(sessions) == 0
            assert record.content_deleted_at is None
        with sessions.begin() as stale:
            cached = stale.get(AssistantTurn, identifier)
            assert cached.message == "private"
            assert purge_batch(sessions) == 1
            refreshed = store.locked_turn(stale, identifier)
            assert refreshed is cached and refreshed.message == ""
            assert refreshed.content_deleted_at is not None
        result = store.update(
            owner.auth,
            conversation.id,
            identifier,
            reply="late",
            tools=[{"result": "late"}],
            status="completed",
        )
        assert result.message == "" and result.reply == "" and result.tools == []
        assert result.status == "failed" and result.reserved_micro_usd == 10
    finally:
        with sessions.begin() as session:
            session.execute(delete(User).where(User.id == owner.owner))
        engine.dispose()


def test_migration_connection_applies_timeouts_on_postgres():
    # Squawk cannot see libpq startup options in offline SQL. Verify the actual
    # server settings, without suppressing warnings or self-approving the migration.
    engine = make_engine(Settings(), migration=True)
    try:
        with engine.connect() as connection:
            assert connection.scalar(select(func.current_setting("lock_timeout"))) == "1s"
            assert connection.scalar(select(func.current_setting("statement_timeout"))) == "5s"
    finally:
        engine.dispose()


@pytest.mark.parametrize("same_owner", [True, False])
def test_concurrent_admissions_share_a_durable_budget(same_owner):
    engine = make_engine(Settings())
    sessions = sessionmaker(engine, expire_on_commit=False)
    owners = [seed(sessions), seed(sessions)]
    policy = AssistantSettings(
        enabled=True,
        daily_budget_micro_usd=10,
        turn_reserve_micro_usd=10,
        policy_date=datetime.now(UTC).date(),
        policy_model="fixture-model",
    )
    store = Store(sessions, policy, ServiceSettings(environment="ci", integrations_mode="fake"))
    conversations = [
        store.create(owner.auth, ConversationCreate(id=uuid4(), farm_id=owner.farm))
        for owner in owners
    ]
    for owner, conversation in zip(owners, conversations, strict=True):
        store.consent(
            owner.auth,
            conversation.id,
            ConsentGrant(notice_version=NOTICE_VERSION, model="fixture-model"),
        )
    with sessions.begin() as session:
        budget = session.get(AssistantBudget, 1)
        old = budget.day, budget.policy, budget.reserved_micro_usd
        budget.day, budget.policy, budget.reserved_micro_usd = None, None, 0
    barrier = Barrier(2, timeout=10)

    def before_lock(conn, cursor, statement, params, context, many):
        if statement.startswith("SELECT assistant_budget.") and "FOR UPDATE" in statement:
            barrier.wait()

    def admit(index):
        index = 0 if same_owner else index
        try:
            return store.admit(
                owners[index].auth, conversations[index].id, TurnCreate(id=uuid4(), message="Hello")
            )[0].status
        except ApiError as error:
            return error.code

    event.listen(engine, "before_cursor_execute", before_lock)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            results = list(pool.map(admit, [0, 1]))
        expected = "turn_in_progress" if same_owner else "assistant_budget_exhausted"
        assert sorted(results) == sorted(["running", expected])
        with sessions() as session:
            assert session.get(AssistantBudget, 1).reserved_micro_usd == 10
            assert (
                len(
                    list(
                        session.scalars(
                            select(AssistantTurn).where(
                                AssistantTurn.owner_id.in_([owner.owner for owner in owners])
                            )
                        )
                    )
                )
                == 1
            )
            admitted = session.scalar(
                select(AssistantTurn).where(
                    AssistantTurn.owner_id.in_([owner.owner for owner in owners])
                )
            )
            turn_id, conversation_id, owner_id = (
                admitted.id,
                admitted.conversation_id,
                admitted.owner_id,
            )
        owner = next(item for item in owners if item.owner == owner_id)
        other = Store(sessions, policy, store.services)
        other.consent(owner.auth, conversation_id, withdraw=True)
        late = store.update(owner.auth, conversation_id, turn_id, reply="late", status="completed")
        assert late.status == "interrupted" and late.reply == ""
        with sessions() as session:
            assert session.get(AssistantBudget, 1).reserved_micro_usd == 10
    finally:
        event.remove(engine, "before_cursor_execute", before_lock)
        with sessions.begin() as session:
            session.execute(delete(User).where(User.id.in_([owner.owner for owner in owners])))
            budget = session.get(AssistantBudget, 1)
            budget.day, budget.policy, budget.reserved_micro_usd = old
        engine.dispose()
