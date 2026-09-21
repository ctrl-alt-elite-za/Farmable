"""Owned farm records, retry-safe synchronization, and deterministic demo data."""

from collections.abc import Sequence
from datetime import UTC, date, datetime
from decimal import Decimal
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.orm import Session

from farmable_backend.models import (
    Farm,
    FarmTask,
    FinancialRecord,
    Observation,
    Planting,
    Section,
    SyncChange,
    SyncMutation,
    User,
)


class RecordConflictError(ValueError):
    """A client mutation conflicts with an owned record or tombstone."""


class RecordNotFoundError(LookupError):
    """The record does not exist in the caller's ownership scope."""


class FarmRecordRepository:
    """Small ORM boundary for the synchronization behavior required by the demo."""

    def __init__(self, session: Session, owner_id: UUID) -> None:
        self.session = session
        self.owner_id = owner_id

    def _section(self, section_id: UUID) -> Section:
        section = self.session.scalar(
            select(Section).where(
                Section.id == section_id,
                Section.owner_id == self.owner_id,
                Section.deleted_at.is_(None),
            )
        )
        if section is None:
            raise RecordNotFoundError("section not found")
        return section

    def _replayed_observation(self, mutation_id: UUID) -> Observation | None:
        mutation = self.session.scalar(
            select(SyncMutation).where(SyncMutation.mutation_id == mutation_id)
        )
        if mutation is None:
            return None
        if mutation.owner_id != self.owner_id:
            raise RecordConflictError("mutation id belongs to another owner")
        if mutation.operation != "create" or mutation.record_type != "observation":
            raise RecordConflictError("mutation id was already used for another operation")
        observation = self.session.scalar(
            select(Observation).where(
                Observation.id == mutation.record_id,
                Observation.owner_id == self.owner_id,
            )
        )
        if observation is None:
            raise RecordConflictError("mutation result no longer exists")
        return observation

    def create_observation(
        self,
        *,
        mutation_id: UUID,
        observation_id: UUID,
        section_id: UUID,
        type: str,
        note: str,
        health_status: str | None = None,
        action_taken: str | None = None,
        local_media_id: UUID | None = None,
        created_by_voice: bool = False,
        created_at: datetime | None = None,
    ) -> Observation:
        """Create once, or return the original logical result for an exact retry key."""
        replayed = self._replayed_observation(mutation_id)
        if replayed is not None:
            return replayed

        existing = self.session.get(Observation, observation_id)
        if existing is not None:
            if existing.deleted_at is not None:
                raise RecordConflictError("a deleted observation cannot be recreated")
            raise RecordConflictError("observation id already exists")

        section = self._section(section_id)
        observation = Observation(
            id=observation_id,
            farm_id=section.farm_id,
            owner_id=self.owner_id,
            section_id=section.id,
            type=type,
            note=note,
            health_status=health_status,
            action_taken=action_taken,
            local_media_id=local_media_id,
            created_by_voice=created_by_voice,
            **({"created_at": created_at, "updated_at": created_at} if created_at else {}),
        )
        mutation = SyncMutation(
            mutation_id=mutation_id,
            farm_id=section.farm_id,
            owner_id=self.owner_id,
            operation="create",
            record_type="observation",
            record_id=observation.id,
        )
        self.session.add_all((observation, mutation))
        self.session.flush()
        self.session.add(
            SyncChange(
                farm_id=section.farm_id,
                owner_id=self.owner_id,
                mutation_id=mutation.id,
                record_type="observation",
                record_id=observation.id,
                operation="create",
                version=observation.version,
            )
        )
        self.session.flush()
        return observation

    def tombstone_observation(self, *, observation_id: UUID, mutation_id: UUID) -> Observation:
        existing_mutation = self.session.scalar(
            select(SyncMutation).where(SyncMutation.mutation_id == mutation_id)
        )
        if existing_mutation is not None:
            if existing_mutation.owner_id != self.owner_id:
                raise RecordConflictError("mutation id belongs to another owner")
            if (
                existing_mutation.operation != "delete"
                or existing_mutation.record_type != "observation"
                or existing_mutation.record_id != observation_id
            ):
                raise RecordConflictError("mutation id was already used for another operation")
            observation = self.session.get(Observation, observation_id)
            if observation is None or observation.owner_id != self.owner_id:
                raise RecordNotFoundError("observation not found")
            return observation

        observation = self.session.scalar(
            select(Observation).where(
                Observation.id == observation_id,
                Observation.owner_id == self.owner_id,
            )
        )
        if observation is None:
            raise RecordNotFoundError("observation not found")
        if observation.deleted_at is None:
            observation.deleted_at = datetime.now(UTC)
            observation.version += 1
            observation.sync_state = "pending"
        mutation = SyncMutation(
            mutation_id=mutation_id,
            farm_id=observation.farm_id,
            owner_id=self.owner_id,
            operation="delete",
            record_type="observation",
            record_id=observation.id,
        )
        self.session.add(mutation)
        self.session.flush()
        self.session.add(
            SyncChange(
                farm_id=observation.farm_id,
                owner_id=self.owner_id,
                mutation_id=mutation.id,
                record_type="observation",
                record_id=observation.id,
                operation="delete",
                version=observation.version,
            )
        )
        self.session.flush()
        return observation

    def observations(self) -> Sequence[Observation]:
        return self.session.scalars(
            select(Observation).where(
                Observation.owner_id == self.owner_id, Observation.deleted_at.is_(None)
            )
        ).all()

    def tasks(self) -> Sequence[FarmTask]:
        return self.session.scalars(
            select(FarmTask).where(
                FarmTask.owner_id == self.owner_id, FarmTask.deleted_at.is_(None)
            )
        ).all()

    def financial_records(self) -> Sequence[FinancialRecord]:
        return self.session.scalars(
            select(FinancialRecord).where(
                FinancialRecord.owner_id == self.owner_id,
                FinancialRecord.deleted_at.is_(None),
            )
        ).all()


DEMO_OWNER_ID = UUID("10000000-0000-4000-8000-000000000001")
DEMO_FARM_ID = UUID("10000000-0000-4000-8000-000000000002")
DEMO_CABBAGE_SECTION_ID = UUID("10000000-0000-4000-8000-000000000003")
DEMO_NORTH_SECTION_ID = UUID("10000000-0000-4000-8000-000000000004")
DEMO_OBSERVATION_ID = UUID("10000000-0000-4000-8000-000000000005")
DEMO_TASK_ID = UUID("10000000-0000-4000-8000-000000000006")
DEMO_PLANTING_ID = UUID("10000000-0000-4000-8000-000000000007")


def seed_demo_farm(session: Session) -> Farm:
    """Create the stable minimum demo state; repeated calls are harmless."""
    existing = session.get(Farm, DEMO_FARM_ID)
    if existing is not None:
        return existing

    owner = session.get(User, DEMO_OWNER_ID)
    if owner is None:
        owner = User(id=DEMO_OWNER_ID)
        session.add(owner)
    farm = Farm(
        id=DEMO_FARM_ID,
        owner_id=DEMO_OWNER_ID,
        name="Mahlangu Demo Farm",
        sync_state="synced",
    )
    cabbage = Section(
        id=DEMO_CABBAGE_SECTION_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        name="Cabbage Field",
        area_m2=Decimal("400.00"),
        sync_state="synced",
    )
    north = Section(
        id=DEMO_NORTH_SECTION_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        name="North Plot",
        area_m2=Decimal("300.00"),
        sync_state="synced",
    )
    planting = Planting(
        id=DEMO_PLANTING_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        section_id=cabbage.id,
        crop="cabbage",
        planted_on=date(2026, 8, 10),
        sync_state="synced",
    )
    observation = Observation(
        id=DEMO_OBSERVATION_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        section_id=cabbage.id,
        type="health",
        note="Lower leaves checked; crop remains suitable for the demo.",
        health_status="normal",
        created_by_voice=False,
        sync_state="synced",
    )
    task = FarmTask(
        id=DEMO_TASK_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        section_id=cabbage.id,
        title="Water Cabbage Field",
        description="Upcoming watering task for the voice-edit demonstration.",
        due_date=date(2026, 9, 25),
        status="pending",
        expected_cost_cents=0,
        sync_state="synced",
    )
    session.add_all((farm, cabbage, north, planting, observation, task))
    session.flush()
    return farm
