"""Generic owner-scoped record mutations over the shared sync ledger (#11)."""

from dataclasses import dataclass
from datetime import date, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from farmable_backend.farm_records import _fingerprint
from farmable_backend.models import (
    CropCalendar,
    CropType,
    Farm,
    FarmTask,
    FinancialRecord,
    Media,
    Observation,
    PhotoAttempt,
    PhotoUpload,
    Planting,
    PlantingCrop,
    SavedPlan,
    Section,
    SectionKind,
    SyncChange,
    SyncMutation,
)
from farmable_backend.planning.history import preserve
from farmable_backend.record_access import ApiError, db_now, section_scope
from farmable_backend.weather_jobs import enqueue_weather

# Security criterion (#11): reject planting dates further than two years from
# today in either direction.
PLANTING_DATE_WINDOW = timedelta(days=730)


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

# Every record kind that can be attached to a section, for cascade delete.
SECTION_ATTACHED = tuple(kind for kind in KINDS.values() if kind.section != "none")


def _validate_planted_on(session: Session, planted_on: date | None) -> None:
    if planted_on is None:
        return
    today = db_now(session).date()
    if not today - PLANTING_DATE_WINDOW <= planted_on <= today + PLANTING_DATE_WINDOW:
        raise ApiError(422, "planted_on_out_of_range")


def _resolve_crop_identity(session: Session, crop: str, crop_type_code: str | None) -> str | None:
    """Validate the optional catalogue identity without rewriting legacy text."""
    if crop_type_code is not None:
        code = crop_type_code.strip().casefold()
        if session.get(CropType, code) is None:
            raise ApiError(422, "unknown_crop_type")
        return code

    # ``crop`` predates the catalogue and remains free text.  Infer a code only
    # when it happens to be an exact catalogue code; otherwise keep the legacy
    # planting valid without inventing a catalogue identity.
    legacy_code = crop.strip().casefold()
    catalogue = session.get(CropType, legacy_code)
    return catalogue.code if catalogue is not None else None


def _resolve_crop_window(
    session: Session, crop_type_code: str, planted_on: date | None
) -> tuple[date | None, date | None]:
    calendar = session.get(CropCalendar, crop_type_code)
    if calendar is None:
        # A catalogue entry without a validated calendar is still a valid
        # identity, but it must not produce dates from illustrative defaults.
        return None, None
    if planted_on is None:
        return None, None
    return (
        planted_on + timedelta(days=calendar.harvest_days_min),
        planted_on + timedelta(days=calendar.harvest_days_max),
    )


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
        section_kind = values.pop("kind", None) if kind.resource == "sections" else None
        crop_type_code = (
            values.pop("crop_type_code", None) if kind.resource == "plantings" else None
        )
        if kind.resource == "plantings":
            if crop_type_code is not None:
                _validate_planted_on(self.session, values.get("planted_on"))
            crop_type_code = _resolve_crop_identity(self.session, values["crop"], crop_type_code)
        record = kind.model(
            id=record_id,
            farm_id=self.farm_id,
            owner_id=self.owner_id,
            sync_state="synced",
            **values,
        )
        self.session.add(record)
        self.session.flush((record,))
        if kind.resource == "sections":
            self.session.add(SectionKind(section_id=record.id, kind=section_kind or "crop"))
            self.session.flush()
        if kind.resource == "plantings":
            self._set_planting_crop(record.id, crop_type_code, values.get("planted_on"))
        return record

    def _set_planting_crop(
        self, planting_id: UUID, crop_type_code: str | None, planted_on: date | None
    ) -> None:
        """Full-replace the companion crop_type_code/harvest window (#11)."""
        existing = self.session.get(PlantingCrop, planting_id)
        if crop_type_code is None:
            if existing is None:
                return
            crop_type_code = existing.crop_type_code
        harvest_from, harvest_to = _resolve_crop_window(self.session, crop_type_code, planted_on)
        if existing is None:
            self.session.add(
                PlantingCrop(
                    planting_id=planting_id,
                    crop_type_code=crop_type_code,
                    harvest_from=harvest_from,
                    harvest_to=harvest_to,
                )
            )
        else:
            existing.crop_type_code = crop_type_code
            existing.harvest_from = harvest_from
            existing.harvest_to = harvest_to
        self.session.flush()

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
                if kind.resource == "plans":
                    preserve(self.session, record)
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
        section_kind = values.pop("kind", None) if kind.resource == "sections" else None
        crop_type_code = (
            values.pop("crop_type_code", None) if kind.resource == "plantings" else None
        )
        if kind.resource == "plantings":
            if crop_type_code is not None and values.get("planted_on") != record.planted_on:
                _validate_planted_on(self.session, values.get("planted_on"))
            crop_type_code = _resolve_crop_identity(self.session, values["crop"], crop_type_code)
        if kind.resource == "plans":
            preserve(self.session, record)
        for name, value in values.items():
            setattr(record, name, value)
        record.version += 1
        record.sync_state = "synced"
        self.session.flush((record,))
        if kind.resource == "sections":
            section_kind_row = self.session.get(SectionKind, record.id)
            if section_kind_row is None:
                self.session.add(SectionKind(section_id=record.id, kind=section_kind or "crop"))
            else:
                section_kind_row.kind = section_kind or "crop"
            self.session.flush()
        if kind.resource == "plantings":
            self._set_planting_crop(record.id, crop_type_code, values.get("planted_on"))
        return record

    def _cascade_delete_section(
        self,
        mutation: SyncMutation,
        section_id: UUID,
        expected_child_versions: dict[UUID, int],
    ) -> None:
        now = db_now(self.session)
        for child in SECTION_ATTACHED:
            rows = list(
                self.session.scalars(
                    select(child.model)
                    .where(
                        child.model.owner_id == self.owner_id,
                        child.model.farm_id == self.farm_id,
                        child.model.section_id == section_id,
                        child.model.deleted_at.is_(None),
                    )
                    .with_for_update()
                )
            )
            for row in rows:
                expected = expected_child_versions.get(row.id)
                if expected is None or expected != row.version:
                    raise ApiError(409, "revision_conflict")
                row.deleted_at = now
                row.version += 1
                row.sync_state = "synced"
                self.session.add(
                    SyncChange(
                        farm_id=self.farm_id,
                        owner_id=self.owner_id,
                        mutation_id=mutation.id,
                        record_type=child.record_type,
                        record_id=row.id,
                        operation="delete",
                        version=row.version,
                    )
                )
            if child.model is Planting:
                for planting_id in (row.id for row in rows):
                    crop_row = self.session.get(PlantingCrop, planting_id)
                    if crop_row is not None:
                        self.session.delete(crop_row)
        section_kind = self.session.get(SectionKind, section_id)
        if section_kind is not None:
            self.session.delete(section_kind)
        # Photo uploads are durable storage intents rather than generic sync
        # records.  Invalidate every attempt and make cleanup immediately
        # claimable, including attempts previously marked cleaned and claims
        # currently held by a worker.  The upload state must not remain
        # ``ready`` or the janitor would intentionally preserve the clean key.
        uploads = list(
            self.session.scalars(
                select(PhotoUpload)
                .where(
                    PhotoUpload.owner_id == self.owner_id,
                    PhotoUpload.farm_id == self.farm_id,
                    PhotoUpload.section_id == section_id,
                )
                .with_for_update()
            )
        )
        cleanup_due = now - timedelta(hours=1, seconds=1)
        for upload in uploads:
            upload.state = "failed"
            upload.error_code = "scope_unavailable"
            attempts = list(
                self.session.scalars(
                    select(PhotoAttempt)
                    .where(PhotoAttempt.upload_id == upload.id)
                    .with_for_update()
                )
            )
            for attempt in attempts:
                attempt.terminal_at = cleanup_due
                attempt.form_expires_at = cleanup_due
                attempt.lease_token = None
                attempt.lease_expires_at = None
                attempt.cleanup_token = None
                attempt.cleanup_expires_at = None
                attempt.cleaned_at = None
        self.session.flush()

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
        cascade = (
            resource == "sections"
            and operation == "delete"
            and (before := self._load(kind, target)) is not None
            and before.deleted_at is None
        )
        try:
            with self.session.begin_nested():
                self.session.add(mutation)
                self.session.flush((mutation,))
                record = self._write(kind, operation, target, values, expected_version)
                if resource == "plans":
                    preserve(self.session, record, "manual")
                if resource == "sections" and operation != "delete":
                    enqueue_weather(self.session, record.boundary)
                if cascade:
                    # Reliability criterion (#11): deleting a section removes
                    # every record attached to it, published to the change
                    # feed under this same mutation so other devices learn
                    # of the cascade too, not only the section tombstone.
                    self._cascade_delete_section(
                        mutation,
                        target,
                        values.pop("expected_child_versions", {}),
                    )
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
