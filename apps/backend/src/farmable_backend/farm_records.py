"""Owner/farm-scoped records and retry-safe synchronization behavior."""

import hashlib
import json
from collections.abc import Mapping, Sequence
from datetime import UTC, datetime
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from farmable_backend.models import (
    Farm,
    FarmTask,
    FinancialRecord,
    Media,
    Observation,
    Section,
    SyncChange,
    SyncMutation,
)


class RecordConflictError(ValueError):
    """A client mutation conflicts with an owned record or previous request."""


class RecordNotFoundError(LookupError):
    """The record does not exist in the caller's ownership scope."""


def _timestamp(value: datetime | None) -> str | None:
    if value is None:
        return None
    if value.utcoffset() is None:
        raise ValueError("created_at must include a timezone")
    return value.astimezone(UTC).isoformat(timespec="microseconds")


def _fingerprint(payload: Mapping[str, Any]) -> str:
    canonical = json.dumps(payload, ensure_ascii=False, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()


class FarmRecordRepository:
    """Transaction-neutral ORM boundary for one owner's farm."""

    def __init__(self, session: Session, owner_id: UUID, farm_id: UUID) -> None:
        self.session = session
        self.owner_id = owner_id
        self.farm_id = farm_id

    def _section(self, section_id: UUID) -> Section:
        section = self.session.scalar(
            select(Section)
            .where(
                Section.id == section_id,
                Section.owner_id == self.owner_id,
                Section.farm_id == self.farm_id,
                Section.deleted_at.is_(None),
            )
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if section is None:
            raise RecordNotFoundError("section not found")
        return section

    def _media(self, media_id: UUID) -> Media:
        media = self.session.scalar(
            select(Media).where(
                Media.id == media_id,
                Media.owner_id == self.owner_id,
                Media.farm_id == self.farm_id,
                Media.deleted_at.is_(None),
            )
        )
        if media is None:
            raise RecordNotFoundError("media not found")
        return media

    def _mutation(self, mutation_id: UUID) -> SyncMutation | None:
        return self.session.scalar(
            select(SyncMutation).where(SyncMutation.mutation_id == mutation_id)
        )

    def _lock_change_stream(self) -> None:
        """Serialize cursor allocation within this owned farm until commit."""
        locked_farm_id = self.session.scalar(
            select(Farm.id)
            .where(Farm.id == self.farm_id, Farm.owner_id == self.owner_id)
            .with_for_update()
        )
        if locked_farm_id is None:
            raise RecordNotFoundError("farm not found")

    def _mutation_or_lock_change_stream(self, mutation_id: UUID) -> SyncMutation | None:
        """Return a replay, or lock the farm and recheck before a new change."""
        existing = self._mutation(mutation_id)
        if existing is not None:
            return existing
        self._lock_change_stream()
        return self._mutation(mutation_id)

    def _replayed_observation(
        self,
        mutation: SyncMutation,
        *,
        operation: str,
        observation_id: UUID,
        request_fingerprint: str,
    ) -> Observation:
        expected = (
            self.owner_id,
            self.farm_id,
            operation,
            "observation",
            observation_id,
            request_fingerprint,
        )
        actual = (
            mutation.owner_id,
            mutation.farm_id,
            mutation.operation,
            mutation.record_type,
            mutation.record_id,
            mutation.request_fingerprint,
        )
        if actual != expected:
            raise RecordConflictError("mutation id is already used for a different request")
        observation = self.session.scalar(
            select(Observation).where(
                Observation.id == mutation.record_id,
                Observation.owner_id == self.owner_id,
                Observation.farm_id == self.farm_id,
            )
        )
        if observation is None:
            raise RecordConflictError("mutation result no longer exists")
        return observation

    def _recover_replay(
        self,
        mutation_id: UUID,
        *,
        operation: str,
        observation_id: UUID,
        request_fingerprint: str,
    ) -> Observation:
        mutation = self._mutation(mutation_id)
        if mutation is None:
            raise RecordConflictError("record conflicts with existing data")
        return self._replayed_observation(
            mutation,
            operation=operation,
            observation_id=observation_id,
            request_fingerprint=request_fingerprint,
        )

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
        """Create once, returning the original result only for an exact retry."""
        request_fingerprint = _fingerprint(
            {
                "action_taken": action_taken,
                "created_at": _timestamp(created_at),
                "created_by_voice": created_by_voice,
                "health_status": health_status,
                "local_media_id": str(local_media_id) if local_media_id else None,
                "note": note,
                "observation_id": str(observation_id),
                "operation": "create",
                "record_type": "observation",
                "section_id": str(section_id),
                "type": type,
            }
        )
        existing_mutation = self._mutation_or_lock_change_stream(mutation_id)
        if existing_mutation is not None:
            return self._replayed_observation(
                existing_mutation,
                operation="create",
                observation_id=observation_id,
                request_fingerprint=request_fingerprint,
            )

        mutation = SyncMutation(
            mutation_id=mutation_id,
            farm_id=self.farm_id,
            owner_id=self.owner_id,
            operation="create",
            record_type="observation",
            record_id=observation_id,
            request_fingerprint=request_fingerprint,
        )
        try:
            with self.session.begin_nested():
                self.session.add(mutation)
                self.session.flush((mutation,))

                existing = self.session.get(Observation, observation_id)
                if (
                    self.session.scalar(
                        select(SyncChange.id)
                        .where(
                            SyncChange.record_type == "observation",
                            SyncChange.record_id == observation_id,
                            SyncChange.operation == "delete",
                        )
                        .limit(1)
                    )
                    is not None
                ):
                    raise RecordConflictError("a deleted observation cannot be recreated")
                if existing is not None:
                    if existing.deleted_at is not None:
                        raise RecordConflictError("a deleted observation cannot be recreated")
                    raise RecordConflictError("observation id already exists")

                section = self._section(section_id)
                if local_media_id is not None:
                    self._media(local_media_id)
                observation = Observation(
                    id=observation_id,
                    farm_id=self.farm_id,
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
                self.session.add(observation)
                self.session.flush((observation,))
                self.session.add(
                    SyncChange(
                        farm_id=self.farm_id,
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
        except IntegrityError:
            return self._recover_replay(
                mutation_id,
                operation="create",
                observation_id=observation_id,
                request_fingerprint=request_fingerprint,
            )

    def tombstone_observation(self, *, observation_id: UUID, mutation_id: UUID) -> Observation:
        request_fingerprint = _fingerprint(
            {
                "observation_id": str(observation_id),
                "operation": "delete",
                "record_type": "observation",
            }
        )
        existing_mutation = self._mutation_or_lock_change_stream(mutation_id)
        if existing_mutation is not None:
            return self._replayed_observation(
                existing_mutation,
                operation="delete",
                observation_id=observation_id,
                request_fingerprint=request_fingerprint,
            )

        mutation = SyncMutation(
            mutation_id=mutation_id,
            farm_id=self.farm_id,
            owner_id=self.owner_id,
            operation="delete",
            record_type="observation",
            record_id=observation_id,
            request_fingerprint=request_fingerprint,
        )
        try:
            with self.session.begin_nested():
                self.session.add(mutation)
                self.session.flush((mutation,))
                observation = self.session.scalar(
                    select(Observation)
                    .where(
                        Observation.id == observation_id,
                        Observation.owner_id == self.owner_id,
                        Observation.farm_id == self.farm_id,
                    )
                    .with_for_update()
                )
                if observation is None:
                    raise RecordNotFoundError("observation not found")
                if observation.deleted_at is None:
                    observation.deleted_at = datetime.now(UTC)
                    observation.version += 1
                    observation.sync_state = "pending"
                    self.session.flush((observation,))
                    self.session.add(
                        SyncChange(
                            farm_id=self.farm_id,
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
        except IntegrityError:
            return self._recover_replay(
                mutation_id,
                operation="delete",
                observation_id=observation_id,
                request_fingerprint=request_fingerprint,
            )

    def observations(self) -> Sequence[Observation]:
        return self.session.scalars(
            select(Observation)
            .where(
                Observation.owner_id == self.owner_id,
                Observation.farm_id == self.farm_id,
                Observation.deleted_at.is_(None),
            )
            .order_by(Observation.created_at, Observation.id)
        ).all()

    def tasks(self) -> Sequence[FarmTask]:
        return self.session.scalars(
            select(FarmTask)
            .where(
                FarmTask.owner_id == self.owner_id,
                FarmTask.farm_id == self.farm_id,
                FarmTask.deleted_at.is_(None),
            )
            .order_by(FarmTask.due_date, FarmTask.id)
        ).all()

    def financial_records(self) -> Sequence[FinancialRecord]:
        return self.session.scalars(
            select(FinancialRecord)
            .where(
                FinancialRecord.owner_id == self.owner_id,
                FinancialRecord.farm_id == self.farm_id,
                FinancialRecord.deleted_at.is_(None),
            )
            .order_by(FinancialRecord.date, FinancialRecord.id)
        ).all()
