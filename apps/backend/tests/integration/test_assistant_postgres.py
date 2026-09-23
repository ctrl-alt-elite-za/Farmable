"""Real PostgreSQL locking: no double admission or global budget overspend."""

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Barrier, Event
from uuid import uuid4

import pytest
from farmable_backend.account import AccountService
from farmable_backend.assistant import retention
from farmable_backend.assistant.privacy import NOTICE_VERSION, ConsentGrant
from farmable_backend.assistant.retention import purge_batch
from farmable_backend.assistant.schemas import ConversationCreate, TurnCreate
from farmable_backend.assistant.settings import AssistantSettings
from farmable_backend.assistant.store import Store
from farmable_backend.auth import PASSWORD_HASHER
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.models import (
    AssistantBudget,
    AssistantTurn,
    AuthIdentity,
    ForecastRun,
    ForecastState,
    PlanRevision,
    SavedPlan,
    SyncChange,
    User,
)
from farmable_backend.planning import service as planning_service
from farmable_backend.planning.contracts import PlanConfirmation, PlanRequest
from farmable_backend.planning.service import Planner
from farmable_backend.record_access import ApiError
from farmable_backend.records_schemas import PlanCreate, PlanUpdate
from farmable_backend.records_service import RecordsService
from sqlalchemy import delete, event, func, select
from sqlalchemy.orm import sessionmaker
from test_assistant import policy, seed
from test_forecasts import bundle

pytestmark = pytest.mark.integration


def test_account_erasure_fences_a_waiting_plan_edit():
    engine = make_engine(Settings())
    sessions = sessionmaker(engine, expire_on_commit=False)
    owner = seed(sessions)
    identifier = uuid4()
    records = RecordsService(sessions)
    records.mutate(
        owner.auth,
        owner.farm,
        "plans",
        "create",
        None,
        PlanCreate(
            mutation_id=uuid4(),
            id=identifier,
            section_id=owner.section,
            plan={"private": "before"},
        ),
    )
    with sessions.begin() as session:
        session.get(AuthIdentity, owner.owner).password_hash = PASSWORD_HASHER.hash(
            "fixture password"
        )
    erasure_locked, writer_waiting, release = Event(), Event(), Event()

    def before_lock(conn, cursor, statement, params, context, many):
        if statement.startswith("SELECT farms.") and "FOR UPDATE" in statement:
            if "ORDER BY farms.id" not in statement:
                writer_waiting.set()

    def after_lock(conn, cursor, statement, params, context, many):
        if statement.startswith("SELECT farms.") and "ORDER BY farms.id FOR UPDATE" in statement:
            erasure_locked.set()
            assert release.wait(10), "erasure never released"

    def edit():
        try:
            records.mutate(
                owner.auth,
                owner.farm,
                "plans",
                "update",
                identifier,
                PlanUpdate(
                    mutation_id=uuid4(),
                    expected_version=1,
                    plan={"private": "late"},
                ),
            )
        except ApiError as error:
            return error.code
        return "unexpected_success"

    event.listen(engine, "before_cursor_execute", before_lock)
    event.listen(engine, "after_cursor_execute", after_lock)
    try:
        with ThreadPoolExecutor(max_workers=2) as pool:
            deleting = pool.submit(
                AccountService(sessions).delete_account, owner.auth, "fixture password"
            )
            try:
                assert erasure_locked.wait(10), "erasure did not lock farm"
                editing = pool.submit(edit)
                assert writer_waiting.wait(10), "edit did not reach farm lock"
            finally:
                release.set()
            deleting.result(timeout=10)
            assert editing.result(timeout=10) == "not_found"
        with sessions() as session:
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(PlanRevision)
                    .where(
                        PlanRevision.owner_id == owner.owner,
                    )
                )
                == 0
            )
            record = session.get(SavedPlan, identifier)
            assert record.deleted_at is not None and record.plan == {"private": "before"}
    finally:
        release.set()
        event.remove(engine, "before_cursor_execute", before_lock)
        event.remove(engine, "after_cursor_execute", after_lock)
        with sessions.begin() as session:
            session.execute(delete(User).where(User.id == owner.owner))
        engine.dispose()


@pytest.mark.parametrize("updating", [False, True])
def test_confirmed_planning_is_atomic_across_replicas(monkeypatch, updating):
    engine = make_engine(Settings())
    sessions = sessionmaker(engine, expire_on_commit=False)
    owner = seed(sessions)
    run_id = "planning-" + uuid4().hex
    fixed_now = datetime(2026, 9, 23, tzinfo=UTC)
    monkeypatch.setattr(planning_service, "db_now", lambda _: fixed_now)
    with sessions.begin() as session:
        state = session.get(ForecastState, 1, with_for_update=True)
        previous = state.active_run_id
        if previous:
            session.get(ForecastRun, previous).status = "superseded"
            session.flush()
        session.add(
            ForecastRun(
                id=run_id,
                source_sha256="0" * 64,
                status="active",
                payload=bundle(run_id),
                failed_checks=[],
            )
        )
        session.flush()
        state.active_run_id = run_id
    service = Planner(sessions, "sample", "fake")
    barrier = Barrier(2, timeout=10)

    def before_lock(conn, cursor, statement, params, context, many):
        if statement.startswith("SELECT farms.") and "FOR UPDATE" in statement:
            barrier.wait()

    try:
        request = PlanRequest(
            section_id=owner.section,
            planting_date="2026-10-01",
            budget_cents=1_000_000,
            money_basis_year=2025,
            crops=[{"crop": "cabbage"}],
            planting_cost_percent=50,
            market_commission_bps=500,
            agent_commission_bps=250,
        )
        preview = service.preview(owner.auth, owner.farm, request)
        payload = PlanConfirmation(
            mutation_id=uuid4(),
            plan_id=uuid4(),
            confirmed=True,
            request=request,
            snapshot_hash=preview.snapshot_hash,
            candidate_id=preview.candidates[0].id,
        )
        if updating:
            service.confirm(owner.auth, owner.farm, payload)
        payloads = (
            [payload, payload]
            if not updating
            else [
                payload.model_copy(update={"mutation_id": uuid4(), "expected_version": 1})
                for _ in range(2)
            ]
        )

        def confirm(value):
            try:
                return (
                    Planner(sessions, "sample", "fake")
                    .confirm(owner.auth, owner.farm, value)
                    .replayed
                )
            except ApiError as error:
                return error.code

        event.listen(engine, "before_cursor_execute", before_lock)
        try:
            with ThreadPoolExecutor(max_workers=2) as pool:
                results = list(pool.map(confirm, payloads))
        finally:
            event.remove(engine, "before_cursor_execute", before_lock)
        assert results.count(False) == 1
        assert results.count("revision_conflict" if updating else True) == 1
        with sessions() as session:
            assert session.get(SavedPlan, payload.plan_id).version == (2 if updating else 1)
            revisions = session.scalars(
                select(PlanRevision)
                .where(PlanRevision.plan_id == payload.plan_id)
                .order_by(PlanRevision.version)
            ).all()
            assert [row.version for row in revisions] == ([1, 2] if updating else [1])
            assert all(row.origin == "planner_confirmation" for row in revisions)
            assert session.scalar(
                select(func.count())
                .select_from(SyncChange)
                .where(SyncChange.owner_id == owner.owner)
            ) == (2 if updating else 1)
    finally:
        with sessions.begin() as session:
            session.execute(delete(User).where(User.id == owner.owner))
            state = session.get(ForecastState, 1, with_for_update=True)
            state.active_run_id = previous
            session.flush()
            session.get(ForecastRun, run_id).status = "superseded"
            session.flush()
            if previous:
                session.get(ForecastRun, previous).status = "active"
            session.execute(delete(ForecastRun).where(ForecastRun.id == run_id))
        engine.dispose()


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
