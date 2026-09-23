"""Generic owner-scoped record mutations over the shared sync ledger (#11)."""

from dataclasses import dataclass
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from farmable_backend.farm_records import _fingerprint
from farmable_backend.models import (
    Farm,
    FarmTask,
    FinancialRecord,
    Media,
    Observation,
    Planting,
    SavedPlan,
    Section,
    SyncChange,
    SyncMutation,
)
from farmable_backend.record_access import ApiError, db_now, section_scope


@dataclass(frozen=True)
class RecordKind:
    """One REST resource and the sync-ledger identity of its rows."""

    resource: str
    record_type: str
    model: type[Any]
    section: str


KINDS: dict[str, RecordKind] = {
    "farms": RecordKind("farms", "farm", Farm, "none"),
    "sections": RecordKind("sections", "section", Section, "none"),
    "plantings": RecordKind("plantings", "planting", Planting, "required"),
    "observations": RecordKind("observations", "observation", Observation, "required"),
    "tasks": RecordKind("tasks", "task", FarmTask, "required"),
    "financials": RecordKind("financials", "financial", FinancialRecord, "optional"),
    "plans": RecordKind("plans", "plan", SavedPlan, "required"),
    "media": RecordKind("media", "media", Media, "optional"),
}

SECTION_REQUIRED = frozenset(kind.resource for kind in KINDS.values() if kind.section == "required")


class SyncRecordRepository:
    """Apply each accepted mutation id exactly once inside one owned farm."""

    def __init__(self, session: Session, owner_id: UUID, farm_id: UUID) -> None:
        self.session = session
        self.owner_id = owner_id
        self.farm_id = farm_id

    def _mutation(self, mutation_id: UUID) -> SyncMutation | None:
        return self.session.scalar(
            select(SyncMutation).where(SyncMutation.mutation_id == mutation_id)
        )

    def _load(self, kind: RecordKind, record_id: UUID, *, lock: bool = False) -> Any:
        model = kind.model
        query = select(model).where(
            model.id == record_id,
            model.owner_id == self.owner_id,
            model.farm_id == self.farm_id,
        )
        return self.session.scalar(query.with_for_update() if lock else query)

    def _replay(
        self,
        mutation: SyncMutation,
        *,
        kind: RecordKind,
        operation: str,
        record_id: UUID,
        fingerprint: str,
    ) -> Any:
        actual = (
            mutation.owner_id,
            mutation.farm_id,
            mutation.operation,
            mutation.record_type,
            mutation.record_id,
            mutation.request_fingerprint,
        )
        expected = (
            self.owner_id,
            self.farm_id,
            operation,
            kind.record_type,
            record_id,
            fingerprint,
        )
        if actual != expected:
            raise ApiError(409, "mutation_conflict")
        record = self._load(kind, record_id)
        if record is None:
            raise ApiError(409, "mutation_conflict")
        return record

    def _create(self, kind: RecordKind, record_id: UUID, values: dict[str, Any]) -> Any:
        if self._load(kind, record_id) is not None:
            raise ApiError(409, "record_exists")
        section_id = values.get("section_id")
        if kind.section == "required" or (kind.section == "optional" and section_id is not None):
            section_scope(self.session, self.owner_id, self.farm_id, section_id)
        record = kind.model(
            id=record_id,
            farm_id=self.farm_id,
            owner_id=self.owner_id,
            sync_state="synced",
            **values,
        )
        self.session.add(record)
        self.session.flush((record,))
        return record

    def _write(
        self,
        kind: RecordKind,
        operation: str,
        record_id: UUID,
        values: dict[str, Any],
        expected_version: int | None,
    ) -> Any:
        if operation == "create":
            return self._create(kind, record_id, values)
        record = self._load(kind, record_id, lock=True)
        if record is None:
            raise ApiError(404, "not_found")
        if operation == "delete":
            # RecordDelete.expected_version is required (PR #59 review: an offline
            # delete that never saw a newer edit must not be able to silently
            # tombstone it), so this is always set here.
            if expected_version != record.version:
                raise ApiError(409, "revision_conflict")
            if record.deleted_at is None:
                record.deleted_at = db_now(self.session)
                record.version += 1
                record.sync_state = "synced"
                self.session.flush((record,))
            return record
        if record.deleted_at is not None:
            raise ApiError(409, "record_deleted")
        if expected_version != record.version:
            raise ApiError(409, "revision_conflict")
        section_id = values.get("section_id")
        if section_id is not None:
            section_scope(self.session, self.owner_id, self.farm_id, section_id)
        for name, value in values.items():
            setattr(record, name, value)
        record.version += 1
        record.sync_state = "synced"
        self.session.flush((record,))
        return record

    def apply(self, *, resource: str, operation: str, record_id: UUID | None, payload: Any) -> Any:
        """Return the replayed record, or write one record and one change row."""
        kind = KINDS[resource]
        target = record_id if record_id is not None else payload.id
        expected_version = getattr(payload, "expected_version", None)
        values = payload.model_dump(exclude={"mutation_id", "expected_version", "id"})
        fingerprint = _fingerprint(
            {
                "fields": payload.model_dump(mode="json"),
                "operation": operation,
                "record_id": str(target),
                "record_type": kind.record_type,
            }
        )
        existing = self._mutation(payload.mutation_id)
        if existing is not None:
            return self._replay(
                existing,
                kind=kind,
                operation=operation,
                record_id=target,
                fingerprint=fingerprint,
            )
        mutation = SyncMutation(
            mutation_id=payload.mutation_id,
            farm_id=self.farm_id,
            owner_id=self.owner_id,
            operation=operation,
            record_type=kind.record_type,
            record_id=target,
            request_fingerprint=fingerprint,
        )
        try:
            with self.session.begin_nested():
                self.session.add(mutation)
                self.session.flush((mutation,))
                record = self._write(kind, operation, target, values, expected_version)
                self.session.add(
                    SyncChange(
                        farm_id=self.farm_id,
                        owner_id=self.owner_id,
                        mutation_id=mutation.id,
                        record_type=kind.record_type,
                        record_id=record.id,
                        operation=operation,
                        version=record.version,
                    )
                )
                self.session.flush()
                return record
        except IntegrityError:
            replay = self._mutation(payload.mutation_id)
            if replay is None:
                raise ApiError(409, "record_conflict") from None
            if replay.request_fingerprint != fingerprint:
                raise ApiError(409, "mutation_conflict") from None
            return self._replay(
                replay,
                kind=kind,
                operation=operation,
                record_id=target,
                fingerprint=fingerprint,
            )
