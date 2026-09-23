"""Real PostgreSQL locking: no double admission or global budget overspend."""

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from threading import Barrier
from uuid import uuid4

import pytest
from farmable_backend.assistant.schemas import ConversationCreate, TurnCreate
from farmable_backend.assistant.settings import AssistantSettings
from farmable_backend.assistant.store import Store
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.models import AssistantBudget, AssistantTurn, User
from farmable_backend.record_access import ApiError
from sqlalchemy import delete, event, select
from sqlalchemy.orm import sessionmaker
from test_assistant import seed

pytestmark = pytest.mark.integration


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
    finally:
        event.remove(engine, "before_cursor_execute", before_lock)
        with sessions.begin() as session:
            session.execute(delete(User).where(User.id.in_([owner.owner for owner in owners])))
            budget = session.get(AssistantBudget, 1)
            budget.day, budget.policy, budget.reserved_micro_usd = old
        engine.dispose()
