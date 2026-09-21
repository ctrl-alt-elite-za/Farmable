"""PostgreSQL-only integrity and concurrency coverage for issue #8."""

from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime
from itertools import pairwise
from threading import Barrier
from uuid import UUID, uuid4

import pytest
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.demo_seed import DEMO_FARM_ID, DEMO_OWNER_ID, seed_demo_farm
from farmable_backend.farm_records import FarmRecordRepository, RecordConflictError
from farmable_backend.models import (
    Farm,
    FarmTask,
    FinancialRecord,
    Media,
    Observation,
    Section,
    SyncChange,
    SyncMutation,
    User,
)
from sqlalchemy import func, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

pytestmark = pytest.mark.integration


@pytest.fixture
def engine():
    value = make_engine(Settings())
    yield value
    value.dispose()


def create_scope(session: Session, *, owner_id: UUID | None = None):
    owner_id = owner_id or uuid4()
    user = session.get(User, owner_id)
    if user is None:
        session.add(User(id=owner_id))
        session.flush()
    farm = Farm(id=uuid4(), owner_id=owner_id, name=f"Farm {uuid4()}")
    session.add(farm)
    session.flush()
    section = Section(farm_id=farm.id, owner_id=owner_id, name="North Plot")
    session.add(section)
    session.flush()
    return owner_id, farm.id, section.id


def remove_owner(engine, owner_id: UUID) -> None:
    with Session(engine) as session:
        user = session.get(User, owner_id)
        if user is not None:
            session.delete(user)
            session.commit()


@pytest.fixture
def farm_scope(engine):
    with Session(engine) as session:
        owner_id, farm_id, section_id = create_scope(session)
        session.commit()
    try:
        yield owner_id, farm_id, section_id
    finally:
        remove_owner(engine, owner_id)


def observation_request(section_id: UUID, observation_id: UUID):
    return {
        "observation_id": observation_id,
        "section_id": section_id,
        "type": "health",
        "note": "Yellow leaves on the south side.",
        "action_taken": "Watered this morning.",
        "created_by_voice": True,
        "created_at": datetime(2026, 9, 21, 8, 30, tzinfo=UTC),
    }


def test_farm_records_database_rejects_cross_tenant_section(engine, farm_scope):
    owner_id, farm_id, section_id = farm_scope
    with Session(engine) as session:
        other_owner, _other_farm, other_section = create_scope(session)
        other_media = Media(
            farm_id=_other_farm,
            owner_id=other_owner,
            section_id=other_section,
            local_id=str(uuid4()),
            media_type="image/jpeg",
        )
        session.add(other_media)
        session.commit()
        other_media_id = other_media.id
    try:
        with Session(engine) as session:
            session.add(
                FarmTask(
                    farm_id=farm_id,
                    owner_id=owner_id,
                    section_id=other_section,
                    title="Must fail",
                    due_date=datetime(2026, 9, 25, tzinfo=UTC).date(),
                )
            )
            with pytest.raises(IntegrityError):
                session.commit()
            session.rollback()
            session.add(
                Observation(
                    farm_id=farm_id,
                    owner_id=owner_id,
                    section_id=section_id,
                    local_media_id=other_media_id,
                    type="health",
                    note="Must fail",
                )
            )
            with pytest.raises(IntegrityError):
                session.commit()
            session.rollback()
            session.add(
                FinancialRecord(
                    farm_id=farm_id,
                    owner_id=owner_id,
                    type="expense",
                    category="water",
                    amount_cents=-1,
                    date=datetime(2026, 9, 21, tzinfo=UTC).date(),
                )
            )
            with pytest.raises(IntegrityError):
                session.commit()
    finally:
        remove_owner(engine, other_owner)


def test_farm_records_database_rejects_cross_tenant_mutation_change(engine, farm_scope):
    owner_id, farm_id, _section_id = farm_scope
    with Session(engine) as session:
        other_owner, other_farm, _other_section = create_scope(session)
        mutation = SyncMutation(
            mutation_id=uuid4(),
            farm_id=other_farm,
            owner_id=other_owner,
            operation="create",
            record_type="observation",
            record_id=uuid4(),
            request_fingerprint="a" * 64,
        )
        session.add(mutation)
        session.commit()
        mutation_id = mutation.id
    try:
        with Session(engine) as session:
            session.add(
                SyncChange(
                    farm_id=farm_id,
                    owner_id=owner_id,
                    mutation_id=mutation_id,
                    record_type="observation",
                    record_id=uuid4(),
                    operation="create",
                    version=1,
                )
            )
            with pytest.raises(IntegrityError):
                session.commit()
    finally:
        remove_owner(engine, other_owner)


def test_farm_records_concurrent_exact_replay_creates_one_change(engine, farm_scope):
    owner_id, farm_id, section_id = farm_scope
    mutation_id, observation_id = uuid4(), uuid4()
    request = observation_request(section_id, observation_id)
    barrier = Barrier(2)

    def create() -> UUID:
        with Session(engine) as session:
            barrier.wait(timeout=10)
            result = FarmRecordRepository(session, owner_id, farm_id).create_observation(
                mutation_id=mutation_id, **request
            )
            session.commit()
            return result.id

    with ThreadPoolExecutor(max_workers=2) as executor:
        results = list(executor.map(lambda _index: create(), range(2)))

    assert results == [observation_id, observation_id]
    with Session(engine) as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(Observation)
                .where(Observation.id == observation_id)
            )
            == 1
        )
        assert (
            session.scalar(
                select(func.count())
                .select_from(SyncMutation)
                .where(SyncMutation.mutation_id == mutation_id)
            )
            == 1
        )
        assert (
            session.scalar(
                select(func.count())
                .select_from(SyncChange)
                .where(SyncChange.record_id == observation_id)
            )
            == 1
        )


def test_farm_records_constraint_failure_preserves_outer_transaction(engine, farm_scope):
    owner_id, farm_id, section_id = farm_scope
    with Session(engine) as session:
        repository = FarmRecordRepository(session, owner_id, farm_id)
        invalid = observation_request(section_id, uuid4())
        invalid["type"] = "x" * 101

        with pytest.raises(RecordConflictError, match="existing data"):
            repository.create_observation(mutation_id=uuid4(), **invalid)

        valid_id = uuid4()
        repository.create_observation(
            mutation_id=uuid4(), **observation_request(section_id, valid_id)
        )
        session.commit()

    with Session(engine) as session:
        assert session.get(Observation, valid_id) is not None


def test_farm_records_tombstone_retry_and_change_cursor_are_stable(engine, farm_scope):
    owner_id, farm_id, section_id = farm_scope
    first_id, second_id = uuid4(), uuid4()
    with Session(engine) as session:
        repository = FarmRecordRepository(session, owner_id, farm_id)
        repository.create_observation(
            mutation_id=uuid4(), **observation_request(section_id, first_id)
        )
        repository.create_observation(
            mutation_id=uuid4(), **observation_request(section_id, second_id)
        )
        session.commit()
    delete_mutation = uuid4()
    with Session(engine) as session:
        repository = FarmRecordRepository(session, owner_id, farm_id)
        deleted = repository.tombstone_observation(
            observation_id=first_id, mutation_id=delete_mutation
        )
        session.commit()
        deleted_version = deleted.version
    with Session(engine) as session:
        replayed = FarmRecordRepository(session, owner_id, farm_id).tombstone_observation(
            observation_id=first_id, mutation_id=delete_mutation
        )
        session.commit()
        assert replayed.version == deleted_version
    with Session(engine) as session:
        changes = session.scalars(
            select(SyncChange)
            .where(SyncChange.owner_id == owner_id, SyncChange.farm_id == farm_id)
            .order_by(SyncChange.id)
        ).all()
        assert len(changes) == 3
        assert all(left.id < right.id for left, right in pairwise(changes))


def test_farm_records_demo_seed_is_repeatable_on_postgres(engine):
    remove_owner(engine, DEMO_OWNER_ID)
    try:
        with Session(engine) as session:
            first = seed_demo_farm(session)
            session.commit()
            assert first.id == DEMO_FARM_ID
        with Session(engine) as session:
            second = seed_demo_farm(session)
            session.commit()
            assert second.id == DEMO_FARM_ID
        with Session(engine) as session:
            assert session.scalar(select(func.count()).select_from(Farm)) >= 1
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(Observation)
                    .where(Observation.farm_id == DEMO_FARM_ID)
                )
                == 1
            )
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(FarmTask)
                    .where(FarmTask.farm_id == DEMO_FARM_ID)
                )
                == 1
            )
    finally:
        remove_owner(engine, DEMO_OWNER_ID)
