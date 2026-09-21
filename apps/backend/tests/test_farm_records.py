from datetime import UTC, date, datetime
from uuid import UUID, uuid4

import pytest
from farmable_backend.farm_records import (
    DEMO_OWNER_ID,
    FarmRecordRepository,
    RecordConflictError,
    seed_demo_farm,
)
from farmable_backend.models import (
    Base,
    Farm,
    FarmTask,
    FinancialRecord,
    Observation,
    Section,
    SyncMutation,
    User,
)
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session


@pytest.fixture
def session():
    engine = create_engine("sqlite+pysqlite:///:memory:")
    Base.metadata.create_all(engine)
    with Session(engine) as db:
        yield db
    engine.dispose()


def owned_section(session: Session, owner_id: UUID) -> Section:
    user = User(id=owner_id)
    farm = Farm(id=uuid4(), owner_id=owner_id, name=f"Farm {owner_id}")
    section = Section(farm_id=farm.id, owner_id=owner_id, name="Field")
    session.add_all((user, farm, section))
    session.flush()
    return section


def test_client_uuid_and_duplicate_mutation_return_one_observation(session: Session):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    repository = FarmRecordRepository(session, owner_id)
    observation_id = uuid4()
    mutation_id = uuid4()
    created_at = datetime(2026, 9, 21, 8, 30, tzinfo=UTC)

    created = repository.create_observation(
        mutation_id=mutation_id,
        observation_id=observation_id,
        section_id=section.id,
        type="health",
        note="Leaves are yellow.",
        created_by_voice=True,
        created_at=created_at,
    )
    replayed = repository.create_observation(
        mutation_id=mutation_id,
        observation_id=uuid4(),
        section_id=section.id,
        type="health",
        note="A retry may carry a regenerated local object id.",
    )

    assert created.id == observation_id
    assert created.created_at.replace(tzinfo=UTC) == created_at
    assert replayed.id == observation_id
    assert session.scalar(select(func.count()).select_from(Observation)) == 1
    assert session.scalar(select(func.count()).select_from(SyncMutation)) == 1


def test_owned_queries_never_leak_observations_tasks_or_finances(session: Session):
    first_owner, second_owner = uuid4(), uuid4()
    first = owned_section(session, first_owner)
    second = owned_section(session, second_owner)
    for owner_id, section in ((first_owner, first), (second_owner, second)):
        session.add_all(
            (
                Observation(
                    farm_id=section.farm_id,
                    owner_id=owner_id,
                    section_id=section.id,
                    type="note",
                    note=str(owner_id),
                ),
                FarmTask(
                    farm_id=section.farm_id,
                    owner_id=owner_id,
                    section_id=section.id,
                    title=str(owner_id),
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

    repository = FarmRecordRepository(session, first_owner)
    assert {record.owner_id for record in repository.observations()} == {first_owner}
    assert {record.owner_id for record in repository.tasks()} == {first_owner}
    assert {record.owner_id for record in repository.financial_records()} == {first_owner}


def test_mutation_id_cannot_be_replayed_by_another_owner(session: Session):
    first_owner, second_owner = uuid4(), uuid4()
    first = owned_section(session, first_owner)
    second = owned_section(session, second_owner)
    mutation_id = uuid4()
    FarmRecordRepository(session, first_owner).create_observation(
        mutation_id=mutation_id,
        observation_id=uuid4(),
        section_id=first.id,
        type="note",
        note="Owned by the first farmer",
    )

    with pytest.raises(RecordConflictError, match="another owner"):
        FarmRecordRepository(session, second_owner).create_observation(
            mutation_id=mutation_id,
            observation_id=uuid4(),
            section_id=second.id,
            type="note",
            note="Must not receive the first farmer's result",
        )


def test_tombstone_is_hidden_and_cannot_be_resurrected(session: Session):
    owner_id = uuid4()
    section = owned_section(session, owner_id)
    repository = FarmRecordRepository(session, owner_id)
    observation_id = uuid4()
    repository.create_observation(
        mutation_id=uuid4(),
        observation_id=observation_id,
        section_id=section.id,
        type="health",
        note="Original",
    )
    deleted = repository.tombstone_observation(observation_id=observation_id, mutation_id=uuid4())

    assert deleted.deleted_at is not None
    assert repository.observations() == []
    with pytest.raises(RecordConflictError, match="cannot be recreated"):
        repository.create_observation(
            mutation_id=uuid4(),
            observation_id=observation_id,
            section_id=section.id,
            type="health",
            note="Resurrection attempt",
        )


def test_demo_seed_is_deterministic_and_contains_voice_demo_records(session: Session):
    first = seed_demo_farm(session)
    second = seed_demo_farm(session)
    repository = FarmRecordRepository(session, DEMO_OWNER_ID)

    assert second.id == first.id
    assert [record.note for record in repository.observations()] == [
        "Lower leaves checked; crop remains suitable for the demo."
    ]
    assert [task.title for task in repository.tasks()] == ["Water Cabbage Field"]
    assert session.scalar(select(func.count()).select_from(Farm)) == 1
