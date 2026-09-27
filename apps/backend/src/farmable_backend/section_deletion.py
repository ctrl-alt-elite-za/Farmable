"""Bounded erasure in the photo janitor; storage I/O never holds database locks."""

import logging
from contextlib import contextmanager
from datetime import timedelta
from uuid import uuid4

from sqlalchemy import delete, or_, select, update

from farmable_backend import record_access
from farmable_backend.models import (
    CropDiagnosis,
    Farm,
    FarmTask,
    FinancialRecord,
    Media,
    Observation,
    PhotoAttempt,
    PhotoUpload,
    PlanRevision,
    Planting,
    PlantingCrop,
    SavedPlan,
    Section,
    SectionDeletion,
)
from farmable_backend.record_access import utc

logger = logging.getLogger(__name__)
RETRY_DELAYS = (10, 60, 300)  # Initial attempt plus at most three retries.
LEASE = timedelta(minutes=5)


class SectionDeletionJobs:
    def __init__(self, sessions):
        self.sessions = sessions

    def enqueue_existing(self):
        """Bounded catch-up for tombstones made before durable erasure existed."""
        with self.sessions() as session:
            candidates = list(
                session.execute(
                    select(Section.id, Section.farm_id)
                    .where(
                        Section.deleted_at.is_not(None),
                        ~select(SectionDeletion.section_id)
                        .where(SectionDeletion.section_id == Section.id)
                        .exists(),
                    )
                    .order_by(Section.id)
                    .limit(20)
                )
            )
        for section_id, farm_id in candidates:
            with self.sessions.begin() as session:
                session.scalar(select(Farm).where(Farm.id == farm_id).with_for_update())
                section = session.get(Section, section_id, with_for_update=True)
                if (
                    section is None
                    or section.deleted_at is None
                    or session.get(SectionDeletion, section_id) is not None
                ):
                    continue
                now = record_access.db_now(session)
                job = SectionDeletion(
                    section_id=section_id,
                    farm_id=section.farm_id,
                    owner_id=section.owner_id,
                    next_attempt_at=now,
                )
                session.add(job)
                session.execute(
                    update(CropDiagnosis)
                    .where(
                        *self.scope(CropDiagnosis, job),
                        CropDiagnosis.state.in_(("queued", "processing")),
                    )
                    .values(
                        state="cancelled",
                        result=None,
                        error=None,
                        withdrawn_at=now,
                        updated_at=now,
                        lease_token=None,
                        lease_expires_at=None,
                    )
                )
                uploads = select(PhotoUpload.id).where(*self.scope(PhotoUpload, job))
                session.execute(
                    update(PhotoAttempt)
                    .where(
                        PhotoAttempt.upload_id.in_(uploads),
                    )
                    .values(
                        terminal_at=now,
                        lease_token=None,
                        cleanup_token=None,
                        cleanup_expires_at=None,
                        cleaned_at=None,
                    )
                )
                session.execute(
                    update(PhotoUpload)
                    .where(
                        *self.scope(PhotoUpload, job),
                    )
                    .values(state="failed", error_code="scope_unavailable")
                )

    @contextmanager
    def locked(self, section_id):
        with self.sessions.begin() as session:
            initial = session.get(SectionDeletion, section_id)
            if initial is None:
                yield session, None
                return
            # Same parent-first ordering as record/diagnosis/photo mutations.
            session.scalar(select(Farm).where(Farm.id == initial.farm_id).with_for_update())
            section = session.scalar(
                select(Section)
                .where(
                    Section.id == section_id,
                    Section.owner_id == initial.owner_id,
                    Section.farm_id == initial.farm_id,
                )
                .with_for_update()
                .execution_options(populate_existing=True)
            )
            job = session.scalar(
                select(SectionDeletion)
                .where(
                    SectionDeletion.section_id == section_id,
                )
                .with_for_update()
                .execution_options(populate_existing=True)
            )
            if section is None or section.deleted_at is None:
                raise ValueError("section_not_deleted")
            yield session, job

    @staticmethod
    def scope(model, job):
        return (
            model.section_id == job.section_id,
            model.owner_id == job.owner_id,
            model.farm_id == job.farm_id,
        )

    @classmethod
    def uploads(cls, session, job):
        return list(
            session.scalars(
                select(PhotoUpload).where(*cls.scope(PhotoUpload, job)).with_for_update()
            )
        )

    @classmethod
    def attempts(cls, session, job):
        uploads = select(PhotoUpload.id).where(*cls.scope(PhotoUpload, job))
        return list(
            session.scalars(
                select(PhotoAttempt).where(PhotoAttempt.upload_id.in_(uploads)).with_for_update()
            )
        )

    @staticmethod
    def owns(job, token, now):
        return (
            job is not None
            and job.status == "processing"
            and job.lease_token == token
            and job.lease_expires_at is not None
            and utc(job.lease_expires_at) > now
        )

    @staticmethod
    def fail(job, now, code):
        job.failures += 1
        job.error_code = code
        job.status = "failed" if job.failures > len(RETRY_DELAYS) else "pending"
        if job.status == "pending":
            job.next_attempt_at = now + timedelta(seconds=RETRY_DELAYS[job.failures - 1])
        job.lease_token = job.lease_expires_at = None

    def candidates(self):
        with self.sessions() as session:
            now = record_access.db_now(session)
            return list(
                session.scalars(
                    select(SectionDeletion.section_id)
                    .where(
                        or_(
                            (SectionDeletion.status == "pending")
                            & (SectionDeletion.next_attempt_at <= now),
                            (SectionDeletion.status == "processing")
                            & (SectionDeletion.lease_expires_at <= now),
                        )
                    )
                    .order_by(SectionDeletion.next_attempt_at, SectionDeletion.section_id)
                    .limit(20)
                )
            )

    def claim(self, section_id):
        with self.locked(section_id) as (session, job):
            now = record_access.db_now(session)
            if job is None or job.status in ("failed", "complete"):
                return None
            if job.status == "processing":
                if utc(job.lease_expires_at) <= now:
                    self.fail(job, now, "worker_interrupted")
                return None
            if utc(job.next_attempt_at) > now:
                return None
            # Waiting for issued forms/in-flight writes is not a failed attempt.
            ready_at = now
            for attempt in self.attempts(session, job):
                if attempt.cleaned_at is not None:
                    continue
                if attempt.terminal_at is None:
                    raise ValueError("photo_not_terminal")
                ready_at = max(
                    ready_at,
                    utc(attempt.terminal_at) + timedelta(hours=1),
                    utc(attempt.form_expires_at) + timedelta(microseconds=1),
                )
                for deadline in (attempt.lease_expires_at, attempt.cleanup_expires_at):
                    if deadline is not None:
                        ready_at = max(ready_at, utc(deadline))
            if ready_at > now:
                job.next_attempt_at = ready_at
                return None
            job.status, job.lease_token = "processing", uuid4()
            job.lease_expires_at = now + LEASE
            return job.lease_token

    def batch(self, section_id, token):
        with self.locked(section_id) as (session, job):
            now = record_access.db_now(session)
            if not self.owns(job, token, now):
                return None
            uploads = {row.id: row for row in self.uploads(session, job)}
            attempts = [row for row in self.attempts(session, job) if row.cleaned_at is None]
            # A missing durable object manifest must not become a false cleanup success.
            unknown = session.scalar(
                select(Media.id)
                .where(
                    *self.scope(Media, job),
                    Media.object_key.is_not(None),
                    Media.id.not_in([row.media_id for row in uploads.values()]),
                )
                .limit(1)
            )
            if unknown is not None:
                raise ValueError("photo_manifest_missing")
            return [(uploads[row.upload_id], row) for row in attempts[:100]]

    def cleaned(self, section_id, token, attempt_id):
        with self.locked(section_id) as (session, job):
            now = record_access.db_now(session)
            if not self.owns(job, token, now):
                return False
            attempt = session.get(PhotoAttempt, attempt_id, with_for_update=True)
            attempt.cleaned_at = now
            job.lease_expires_at = now + LEASE
            return True

    def finish(self, section_id, token):
        with self.locked(section_id) as (session, job):
            now = record_access.db_now(session)
            if not self.owns(job, token, now):
                return False
            if any(row.cleaned_at is None for row in self.attempts(session, job)):
                job.status, job.next_attempt_at = "pending", now
                job.lease_token = job.lease_expires_at = None
                return False  # Successful bounded batch; no retry budget consumed.
            # Keep the section tombstone and content-free sync receipts for offline clients.
            # Media tombstones can be referenced by other observations: detach and scrub,
            # rather than deleting an unrelated section's observation or breaking its FK.
            for model in (
                CropDiagnosis,
                PlanRevision,
                Observation,
                FarmTask,
                FinancialRecord,
                SavedPlan,
            ):
                session.execute(delete(model).where(*self.scope(model, job)))
            planting_ids = select(Planting.id).where(*self.scope(Planting, job))
            session.execute(delete(PlantingCrop).where(PlantingCrop.planting_id.in_(planting_ids)))
            session.execute(delete(Planting).where(*self.scope(Planting, job)))
            session.execute(
                update(Media)
                .where(*self.scope(Media, job))
                .values(section_id=None, object_key=None)
            )
            upload_ids = select(PhotoUpload.id).where(*self.scope(PhotoUpload, job))
            session.execute(delete(PhotoAttempt).where(PhotoAttempt.upload_id.in_(upload_ids)))
            session.execute(delete(PhotoUpload).where(*self.scope(PhotoUpload, job)))
            job.status, job.completed_at, job.error_code = "complete", now, None
            job.lease_token = job.lease_expires_at = None
            return True

    def clean_batch(self, storage_factory, should_stop):
        self.enqueue_existing()
        for section_id in self.candidates():
            if should_stop():
                return
            token = self.claim(section_id)
            if token is None:
                continue
            try:
                batch = self.batch(section_id, token)
                if batch is None:
                    continue
                for upload, attempt in batch:
                    if should_stop():
                        return  # Durable lease expiry recovers an interrupted worker.
                    storage = storage_factory()
                    storage.private()
                    if not storage.cleanup(
                        upload, attempt, keep_clean=False, should_stop=should_stop
                    ):
                        # The adapter bounds generations per pass. More pages are work,
                        # not a provider failure; retain the manifest and resume later.
                        with self.locked(section_id) as (session, job):
                            if self.owns(job, token, record_access.db_now(session)):
                                job.status = "pending"
                                job.next_attempt_at = record_access.db_now(session)
                                job.lease_token = job.lease_expires_at = None
                        break
                    if not self.cleaned(section_id, token, attempt.id):
                        break
                else:
                    self.finish(section_id, token)
            except Exception:
                logger.warning("Section cleanup deferred")
                with self.locked(section_id) as (session, job):
                    now = record_access.db_now(session)
                    if self.owns(job, token, now):
                        self.fail(job, now, "cleanup_unavailable")
