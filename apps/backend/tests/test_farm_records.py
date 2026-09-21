from datetime import UTC, date, datetime
from typing import TypedDict
from uuid import UUID, uuid4

import pytest
from farmable_backend.demo_seed import DEMO_FARM_ID, DEMO_OWNER_ID, seed_demo_farm
from farmable_backend.farm_records import (
    FarmRecordRepository,
    RecordConflictError,
    RecordNotFoundError,
)
from farmable_backend.models import (
    Base,
    Farm,
    FarmTask,
    FinancialRecord,
    Observation,
    Section,
    SyncChange,
    SyncMutation,
    User,
)
from sqlalchemy import create_engine, event, func, select
from sqlalchemy.orm import Session


@pytest.fixture
def session():
    engine = create_engine("sqlite+pysqlite:///:memory:")

    @event.listens_for(engine, "connect")
    def enable_foreign_keys(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()  # raw-sql: allow -- SQLite test configuration.
        cursor.execute("PRAGMA foreign_keys=ON")  # raw-sql: allow -- SQLite test configuration.
        cursor.close()

    Base.metadata.create_all(engine)
    with Session(engine) as db:
        yield db
    engine.dispose()


def owned_section(session: Session, owner_id: UUID, *, farm_id: UUID | None = None) -> Section:
    farm_id = farm_id or uuid4()
    if session.get(User, owner_id) is None:
        session.add(User(id=owner_id))
        session.flush()
    farm = Farm(id=farm_id, owner_id=owner_id, name=f"Farm {farm_id}")
    session.add(farm)
    session.flush()
    section = Section(farm_id=farm.id, owner_id=owner_id, name="Field")
    session.add(section)
    session.flush()
    return section


class ObservationRequest(TypedDict):
    observation_id: UUID
    section_id: UUID
    type: str
    note: str
    created_by_voice: bool
    created_at: datetime


def observation_request(section: Section, observation_id: UUID) -> ObservationRequest:
    return {
        "observation_id": observation_id,
        "section_id": section.id,
        "type": "health",
        "note": "Leaves are yellow.",
        "created_by_voice": True,
        "created_at": datetime(2026, 9, 21, 8, 30, tzinfo=UTC),
    }


def test_client_uuid_and_exact_mutation_replay_return_one_observation(session: Session):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    repository = FarmRecordRepository(session, owner_id, section.farm_id)
    observation_id = uuid4()
    mutation_id = uuid4()
    request = observation_request(section, observation_id)

    created = repository.create_observation(mutation_id=mutation_id, **request)
    replayed = repository.create_observation(mutation_id=mutation_id, **request)

    assert created.id == observation_id
    assert created.created_at.replace(tzinfo=UTC) == request["created_at"]
    assert replayed is created
    assert session.scalar(select(func.count()).select_from(Observation)) == 1
    assert session.scalar(select(func.count()).select_from(SyncMutation)) == 1
    assert session.scalar(select(func.count()).select_from(SyncChange)) == 1


@pytest.mark.parametrize("changed", ["record", "payload"])
def test_mutation_key_reuse_with_different_request_is_rejected(session: Session, changed: str):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    repository = FarmRecordRepository(session, owner_id, section.farm_id)
    mutation_id = uuid4()
    request = observation_request(section, uuid4())
    repository.create_observation(mutation_id=mutation_id, **request)
    if changed == "record":
        request["observation_id"] = uuid4()
    else:
        request["note"] = "A different observation"

    with pytest.raises(RecordConflictError, match="different request"):
        repository.create_observation(mutation_id=mutation_id, **request)


def test_queries_are_scoped_to_both_owner_and_farm(session: Session):
    first_owner, second_owner = uuid4(), uuid4()
    first = owned_section(session, first_owner)
    same_owner_other_farm = owned_section(session, first_owner)
    second = owned_section(session, second_owner)
    for owner_id, section in (
        (first_owner, first),
        (first_owner, same_owner_other_farm),
        (second_owner, second),
    ):
        session.add_all(
            (
                Observation(
                    farm_id=section.farm_id,
                    owner_id=owner_id,
                    section_id=section.id,
                    type="note",
                    note=str(section.farm_id),
                ),
                FarmTask(
                    farm_id=section.farm_id,
                    owner_id=owner_id,
                    section_id=section.id,
                    title=str(section.farm_id),
                    due_date=date(2026, 9, 25),
                    status="pending",
                ),
                FinancialRecord(
                    farm_id=section.farm_id,
                    owner_id=owner_id,
                    section_id=section.id,
                    type="expense",
                    category="water",
                    amount_cents=500,
                    date=date(2026, 9, 21),
                ),
            )
        )
    session.flush()

    repository = FarmRecordRepository(session, first_owner, first.farm_id)
    assert {record.farm_id for record in repository.observations()} == {first.farm_id}
    assert {record.farm_id for record in repository.tasks()} == {first.farm_id}
    assert {record.farm_id for record in repository.financial_records()} == {first.farm_id}


def test_mutation_id_cannot_be_replayed_by_another_owner(session: Session):
    first_owner, second_owner = uuid4(), uuid4()
    first = owned_section(session, first_owner)
    second = owned_section(session, second_owner)
    mutation_id = uuid4()
    FarmRecordRepository(session, first_owner, first.farm_id).create_observation(
        mutation_id=mutation_id, **observation_request(first, uuid4())
    )

    with pytest.raises(RecordConflictError, match="different request"):
        FarmRecordRepository(session, second_owner, second.farm_id).create_observation(
            mutation_id=mutation_id, **observation_request(second, uuid4())
        )


def test_tombstone_retry_is_stable_and_record_cannot_be_resurrected(session: Session):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    repository = FarmRecordRepository(session, owner_id, section.farm_id)
    observation_id = uuid4()
    repository.create_observation(
        mutation_id=uuid4(), **observation_request(section, observation_id)
    )
    mutation_id = uuid4()

    deleted = repository.tombstone_observation(
        observation_id=observation_id, mutation_id=mutation_id
    )
    deleted_version = deleted.version
    replayed = repository.tombstone_observation(
        observation_id=observation_id, mutation_id=mutation_id
    )

    assert replayed is deleted
    assert replayed.version == deleted_version
    assert repository.observations() == []
    assert session.scalar(select(func.count()).select_from(SyncChange)) == 2
    with pytest.raises(RecordConflictError, match="cannot be recreated"):
        repository.create_observation(
            mutation_id=uuid4(), **observation_request(section, observation_id)
        )


def test_missing_section_leaves_outer_transaction_usable(session: Session):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    repository = FarmRecordRepository(session, owner_id, section.farm_id)

    with pytest.raises(RecordNotFoundError, match="section"):
        repository.create_observation(
            mutation_id=uuid4(),
            **observation_request(
                Section(id=uuid4(), farm_id=section.farm_id, owner_id=owner_id, name="Missing"),
                uuid4(),
            ),
        )

    created = repository.create_observation(
        mutation_id=uuid4(), **observation_request(section, uuid4())
    )
    assert created in repository.observations()


def test_constraint_failure_rolls_back_only_the_savepoint(session: Session):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    repository = FarmRecordRepository(session, owner_id, section.farm_id)
    invalid = observation_request(section, uuid4())
    invalid["type"] = "x" * 101

    with pytest.raises(RecordConflictError, match="existing data"):
        repository.create_observation(mutation_id=uuid4(), **invalid)

    created = repository.create_observation(
        mutation_id=uuid4(), **observation_request(section, uuid4())
    )
    assert created in repository.observations()
    assert session.scalar(select(func.count()).select_from(SyncMutation)) == 1


def test_created_at_must_be_timezone_aware(session: Session):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    request = observation_request(section, uuid4())
    request["created_at"] = datetime(2026, 9, 21, 8, 30)

    with pytest.raises(ValueError, match="timezone"):
        FarmRecordRepository(session, owner_id, section.farm_id).create_observation(
            mutation_id=uuid4(), **request
        )


def test_demo_seed_is_deterministic_and_contains_voice_demo_records(session: Session):
    first = seed_demo_farm(session)
    second = seed_demo_farm(session)
    repository = FarmRecordRepository(session, DEMO_OWNER_ID, DEMO_FARM_ID)

    assert second.id == first.id
    assert [record.note for record in repository.observations()] == [
        "Lower leaves checked; crop remains suitable for the demo."
    ]
    assert [task.title for task in repository.tasks()] == ["Water Cabbage Field"]
    assert session.scalar(select(func.count()).select_from(Farm)) == 1
