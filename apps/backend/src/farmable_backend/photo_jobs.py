"""Durable intents, fenced leases and publication; no external I/O under locks."""

from contextlib import contextmanager
from datetime import timedelta
from uuid import UUID, uuid4

from sqlalchemy import or_, select

from farmable_backend.gcs_photos import clean_key
from farmable_backend.models import Farm, Media, PhotoAttempt, PhotoUpload, Section, SyncChange
from farmable_backend.photo_policy import MAX_CLAIMS, RETRY_DELAYS
from farmable_backend.record_access import ApiError, db_now, utc
from farmable_backend.records_service import current_attempt


class PhotoJobs:
    def __init__(self, sessions):
        self.sessions = sessions

    @contextmanager
    def locked(self, upload_id: UUID):
        with self.sessions.begin() as session:
            initial = session.get(PhotoUpload, upload_id)
            if initial is None:
                raise ApiError(404, "not_found")
            # The same parent-first order as API writes, including tombstones.
            farm = session.scalar(select(Farm).where(Farm.id == initial.farm_id).with_for_update())
            section = session.scalar(
                select(Section).where(Section.id == initial.section_id).with_for_update()
            )
            upload = session.scalar(
                select(PhotoUpload)
                .where(PhotoUpload.id == upload_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )
            yield session, upload, farm, section

    @staticmethod
    def active(upload, farm, section):
        return (
            farm is not None
            and section is not None
            and farm.deleted_at is None
            and section.deleted_at is None
            and farm.owner_id == upload.owner_id
            and section.owner_id == upload.owner_id
            and section.farm_id == upload.farm_id
        )

    def candidates(self):
        with self.sessions() as session:
            now = db_now(session)
            return list(
                session.scalars(
                    select(PhotoUpload.id)
                    .join(
                        PhotoAttempt,
                        (PhotoAttempt.upload_id == PhotoUpload.id)
                        & (PhotoAttempt.sequence == PhotoUpload.sequence),
                    )
                    .where(
                        or_(
                            (PhotoUpload.state == "queued") & (PhotoAttempt.next_attempt_at <= now),
                            (PhotoUpload.state == "processing")
                            & (PhotoAttempt.lease_expires_at <= now),
                        )
                    )
                    .order_by(PhotoAttempt.next_attempt_at, PhotoUpload.id)
                    .limit(100)
                )
            )

    def claim(self, upload_id):
        with self.locked(upload_id) as (session, upload, farm, section):
            attempt = current_attempt(session, upload, lock=True)
            now = db_now(session)
            if upload.state not in ("queued", "processing"):
                return None
            if upload.state == "processing" and utc(attempt.lease_expires_at) > now:
                return None
            if utc(attempt.next_attempt_at) > now:
                return None
            if not self.active(upload, farm, section) or attempt.attempt_count >= MAX_CLAIMS:
                upload.state = "failed"
                upload.error_code = (
                    "scope_unavailable"
                    if not self.active(upload, farm, section)
                    else "retry_exhausted"
                )
                attempt.terminal_at = now
                attempt.lease_token = None
                attempt.lease_expires_at = None
                return None
            upload.state = "processing"
            attempt.attempt_count += 1
            attempt.lease_token = uuid4()
            attempt.lease_expires_at = now + timedelta(seconds=120)
            return upload, attempt

    @staticmethod
    def owns(upload, attempt, token, now):
        return (
            upload.state == "processing"
            and attempt.lease_token == token
            and attempt.lease_expires_at is not None
            and utc(attempt.lease_expires_at) > now
        )

    def renew(self, upload_id, token):
        with self.locked(upload_id) as (session, upload, _farm, _section):
            attempt = current_attempt(session, upload, lock=True)
            now = db_now(session)
            if not self.owns(upload, attempt, token, now):
                return False
            attempt.lease_expires_at = now + timedelta(seconds=120)
            return True

    def pin(self, upload_id, token, generation):
        with self.locked(upload_id) as (session, upload, _farm, _section):
            attempt = current_attempt(session, upload, lock=True)
            if not self.owns(upload, attempt, token, db_now(session)):
                raise ApiError(409, "lease_lost")
            if attempt.source_generation is None:
                attempt.source_generation = generation
            if attempt.source_generation != generation:
                raise ApiError(409, "generation_changed")
            return upload, attempt

    def descriptor(self, upload_id, token, digest, size, width, height):
        with self.locked(upload_id) as (session, upload, _farm, _section):
            attempt = current_attempt(session, upload, lock=True)
            if not self.owns(upload, attempt, token, db_now(session)):
                raise ApiError(409, "lease_lost")
            if attempt.clean_sha256 is not None and attempt.clean_sha256 != digest:
                raise ApiError(409, "clean_object_conflict")
            attempt.clean_sha256, attempt.clean_size = digest, size
            attempt.width, attempt.height = width, height

    def finish(self, upload_id, token, generation):
        with self.locked(upload_id) as (session, upload, farm, section):
            attempt = current_attempt(session, upload, lock=True)
            now = db_now(session)
            if not self.owns(upload, attempt, token, now):
                raise ApiError(409, "lease_lost")
            if not self.active(upload, farm, section):
                upload.state, upload.error_code = "failed", "scope_unavailable"
            else:
                if not attempt.source_generation or not attempt.clean_sha256:
                    raise ApiError(409, "descriptor_missing")
                session.add(
                    Media(
                        id=upload.media_id,
                        owner_id=upload.owner_id,
                        farm_id=upload.farm_id,
                        section_id=upload.section_id,
                        local_id=str(upload.local_media_id),
                        media_type=upload.content_type,
                        object_key=clean_key(upload, attempt),
                        sync_state="synced",
                    )
                )
                session.flush()
                session.add(
                    SyncChange(
                        farm_id=upload.farm_id,
                        owner_id=upload.owner_id,
                        mutation_id=upload.mutation_row_id,
                        record_type="media",
                        record_id=upload.media_id,
                        operation="create",
                        version=1,
                    )
                )
                attempt.clean_generation = generation
                upload.state, upload.error_code = "ready", None
            attempt.terminal_at = now
            attempt.lease_token = None
            attempt.lease_expires_at = None

    def fail(self, upload_id, token, code, *, transient):
        with self.locked(upload_id) as (session, upload, _farm, _section):
            attempt = current_attempt(session, upload, lock=True)
            now = db_now(session)
            if not self.owns(upload, attempt, token, now):
                return
            upload.error_code = code
            if transient and attempt.attempt_count < MAX_CLAIMS:
                upload.state = "queued"
                attempt.next_attempt_at = now + timedelta(
                    seconds=RETRY_DELAYS[attempt.attempt_count - 1]
                )
            else:
                upload.state = "failed"
                attempt.terminal_at = now
            attempt.lease_token = None
            attempt.lease_expires_at = None

    def cleanup_candidates(self):
        with self.sessions() as session:
            now = db_now(session)
            return list(
                session.execute(
                    select(PhotoUpload.id, PhotoAttempt.id)
                    .join(PhotoAttempt, PhotoAttempt.upload_id == PhotoUpload.id)
                    .where(
                        PhotoAttempt.cleaned_at.is_(None),
                        or_(
                            PhotoAttempt.terminal_at <= now - timedelta(hours=1),
                            (PhotoUpload.state == "awaiting_upload")
                            & (PhotoAttempt.expires_at <= now),
                        ),
                    )
                    .order_by(PhotoAttempt.expires_at, PhotoAttempt.id)
                    .limit(100)
                )
            )

    def cleanup_claim(self, upload_id, attempt_id):
        with self.locked(upload_id) as (session, upload, _farm, _section):
            attempt = session.scalar(
                select(PhotoAttempt)
                .where(PhotoAttempt.id == attempt_id, PhotoAttempt.upload_id == upload_id)
                .with_for_update()
            )
            now = db_now(session)
            if attempt is None or attempt.cleaned_at is not None:
                return None
            if (
                attempt.sequence == upload.sequence
                and upload.state == "awaiting_upload"
                and utc(attempt.expires_at) <= now
            ):
                upload.state = "expired"
                attempt.terminal_at = attempt.expires_at
            if (
                attempt.terminal_at is None
                or utc(attempt.terminal_at) > now - timedelta(hours=1)
                or utc(attempt.form_expires_at) >= now
                or (
                    attempt.cleanup_expires_at is not None and utc(attempt.cleanup_expires_at) > now
                )
                or (attempt.lease_expires_at is not None and utc(attempt.lease_expires_at) > now)
            ):
                return None
            attempt.cleanup_token = uuid4()
            attempt.cleanup_expires_at = now + timedelta(minutes=5)
            keep_clean = upload.state == "ready" and upload.sequence == attempt.sequence
            return upload, attempt, keep_clean

    def cleanup_finish(self, upload_id, attempt_id, token, done):
        with self.locked(upload_id) as (session, upload, _farm, _section):
            attempt = session.scalar(
                select(PhotoAttempt)
                .where(PhotoAttempt.id == attempt_id, PhotoAttempt.upload_id == upload.id)
                .with_for_update()
            )
            if attempt is None or attempt.cleanup_token != token:
                return
            if done:
                attempt.cleaned_at = db_now(session)
            attempt.cleanup_token = None
            attempt.cleanup_expires_at = None

    def requeue_cleanup_if_inactive(self, upload_id, attempt_id) -> bool:
        """Requeue an object published after its section was deleted."""
        try:
            with self.locked(upload_id) as (session, upload, farm, section):
                attempt = session.scalar(
                    select(PhotoAttempt)
                    .where(PhotoAttempt.id == attempt_id, PhotoAttempt.upload_id == upload.id)
                    .with_for_update()
                )
                if self.active(upload, farm, section):
                    return False
                # The durable attempt may have been removed independently,
                # but the worker still owns the in-memory published object.
                if attempt is None:
                    return True
                cleanup_due = db_now(session) - timedelta(hours=1, seconds=1)
                upload.state = "failed"
                upload.error_code = "scope_unavailable"
                attempt.terminal_at = cleanup_due
                attempt.form_expires_at = cleanup_due
                attempt.lease_token = None
                attempt.lease_expires_at = None
                attempt.cleanup_token = None
                attempt.cleanup_expires_at = None
                attempt.cleaned_at = None
                return True
        except ApiError as error:
            # A hard-removed upload has no durable row left to requeue, but its
            # already-published object still needs the worker's best-effort
            # cleanup.  Treat only the missing-row case as inactive; transient
            # or unrelated API failures must not delete a live object.
            return error.status == 404
