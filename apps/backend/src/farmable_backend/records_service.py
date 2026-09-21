"""Short, scoped ORM transactions. No storage I/O belongs in this module."""

import math
from datetime import timedelta
from uuid import UUID, uuid4

from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.farm_records import FarmRecordRepository, _fingerprint
from farmable_backend.models import (
    Farm,
    Media,
    Observation,
    PhotoAttempt,
    PhotoRate,
    PhotoUpload,
    Section,
    SyncMutation,
    User,
)
from farmable_backend.photo_policy import RECOVERABLE_ERRORS, public_photo_error
from farmable_backend.record_access import (
    ApiError,
    authenticate,
    db_now,
    farm_scope,
    section_scope,
    utc,
)
from farmable_backend.records_schemas import (
    FarmView,
    ObservationAck,
    ObservationCreate,
    ObservationView,
    Page,
    SectionView,
    UploadCreate,
    UploadView,
)


def current_attempt(session: Session, upload: PhotoUpload, *, lock: bool = False) -> PhotoAttempt:
    query = select(PhotoAttempt).where(
        PhotoAttempt.upload_id == upload.id, PhotoAttempt.sequence == upload.sequence
    )
    attempt = session.scalar(query.with_for_update() if lock else query)
    if attempt is None:
        raise ApiError(503, "upload_unavailable")
    return attempt


def upload_view(session: Session, upload: PhotoUpload) -> UploadView:
    if (
        upload.state == "ready"
        and session.scalar(
            select(Media.id).where(
                Media.id == upload.media_id,
                Media.owner_id == upload.owner_id,
                Media.farm_id == upload.farm_id,
                Media.section_id == upload.section_id,
                Media.deleted_at.is_(None),
            )
        )
        is None
    ):
        raise ApiError(404, "not_found")
    mutation = session.get(SyncMutation, upload.mutation_row_id)
    if mutation is None:
        raise ApiError(503, "upload_unavailable")
    return UploadView(
        upload_id=upload.id,
        attempt_id=current_attempt(session, upload).id,
        retryable=upload.state == "failed" and upload.error_code in RECOVERABLE_ERRORS,
        mutation_id=mutation.mutation_id,
        entity_id=upload.local_media_id,
        owner_id=upload.owner_id,
        farm_id=upload.farm_id,
        state=upload.state,
        cloud_media_id=upload.media_id if upload.state == "ready" else None,
        error_code=public_photo_error(upload.error_code),
    )


def observation_view(record: Observation) -> ObservationView:
    return ObservationView(
        **{
            name: getattr(record, name)
            for name in ObservationView.model_fields
            if name != "media_id"
        },
        media_id=record.local_media_id,
    )


class RecordsService:
    def __init__(self, sessions: sessionmaker[Session]):
        self.sessions = sessions

    def read(
        self,
        authorization: str | None,
        kind: str,
        farm_id: UUID | None,
        section_id: UUID | None,
        record_id: UUID | None,
        cursor: UUID | None,
        limit: int,
    ):
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            if farm_id is not None:
                farm_scope(session, owner, farm_id)
            if section_id is not None and farm_id is not None:
                section_scope(session, owner, farm_id, section_id)
            model = {"farms": Farm, "sections": Section, "observations": Observation}[kind]
            transform = {
                "farms": FarmView.model_validate,
                "sections": SectionView.model_validate,
                "observations": observation_view,
            }[kind]
            query = select(model).where(model.owner_id == owner, model.deleted_at.is_(None))
            if model is not Farm:
                query = query.where(model.farm_id == farm_id)
            if model is Observation:
                query = query.join(Section, Observation.section_id == Section.id).where(
                    Section.owner_id == owner,
                    Section.farm_id == farm_id,
                    Section.deleted_at.is_(None),
                )
                if section_id is not None:
                    query = query.where(Observation.section_id == section_id)
            if record_id is not None:
                record = session.scalar(query.where(model.id == record_id))
                if record is None:
                    raise ApiError(404, "not_found")
                return transform(record)
            if cursor is not None:
                query = query.where(model.id > cursor)
            records = list(session.scalars(query.order_by(model.id).limit(limit + 1)))
            return Page(
                items=[transform(record) for record in records[:limit]],
                next_cursor=records[limit - 1].id if len(records) > limit else None,
            )

    def observe(self, authorization: str | None, farm_id: UUID, payload: ObservationCreate):
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            farm_scope(session, owner, farm_id, lock=True)
            section_scope(session, owner, farm_id, payload.section_id, lock=True)
            if payload.media_id is not None:
                ready = session.scalar(
                    select(Media.id)
                    .join(PhotoUpload, PhotoUpload.media_id == Media.id)
                    .where(
                        Media.id == payload.media_id,
                        Media.owner_id == owner,
                        Media.farm_id == farm_id,
                        Media.section_id == payload.section_id,
                        Media.deleted_at.is_(None),
                        PhotoUpload.state == "ready",
                        PhotoUpload.owner_id == owner,
                        PhotoUpload.farm_id == farm_id,
                        PhotoUpload.section_id == payload.section_id,
                    )
                )
                if ready is None:
                    raise ApiError(404, "not_found")
            # Do not age out an already accepted mutation. The repository still
            # validates its owner, entity and exact fingerprint on every replay.
            existing = session.scalar(
                select(SyncMutation.id).where(SyncMutation.mutation_id == payload.mutation_id)
            )
            if existing is None:
                now = db_now(session)
                if (
                    not now - timedelta(days=365)
                    <= payload.created_at
                    <= now + timedelta(minutes=5)
                ):
                    raise ApiError(422, "observation_time_out_of_range")
            values = payload.model_dump(exclude={"media_id"})
            record = FarmRecordRepository(session, owner, farm_id).create_observation(
                **values, local_media_id=payload.media_id
            )
            if record.deleted_at is not None:
                raise ApiError(409, "record_deleted")
            record.sync_state = "synced"
            session.flush()
            return ObservationAck(
                mutation_id=payload.mutation_id,
                entity_id=record.id,
                owner_id=owner,
                farm_id=farm_id,
                version=record.version,
                observation=observation_view(record),
            )

    def photo_rate(self, authorization: str | None) -> UUID:
        # Committed separately: malformed/repeated writes also consume admission.
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            session.scalar(select(User).where(User.id == owner).with_for_update())
            now = db_now(session).timestamp()
            rate = session.get(PhotoRate, owner)
            hits = [] if rate is None else [hit for hit in rate.hits if hit > now - 60]
            if len(hits) >= 30:
                raise ApiError(429, "rate_limited", max(1, math.ceil(min(hits) + 60 - now)))
            if rate is None:
                rate = PhotoRate(owner_id=owner, hits=[])
                session.add(rate)
            rate.hits = [*hits, now]
            return owner

    def reserve(self, authorization: str | None, farm_id: UUID, payload: UploadCreate):
        self.photo_rate(authorization)
        try:
            with self.sessions.begin() as session:
                owner = authenticate(session, authorization)
                farm_scope(session, owner, farm_id, lock=True)
                section_scope(session, owner, farm_id, payload.section_id, lock=True)
                fingerprint = _fingerprint(payload.model_dump(mode="json"))
                mutation = session.scalar(
                    select(SyncMutation).where(SyncMutation.mutation_id == payload.mutation_id)
                )
                if mutation is not None:
                    if (
                        mutation.owner_id,
                        mutation.farm_id,
                        mutation.record_type,
                        mutation.operation,
                        mutation.request_fingerprint,
                    ) != (owner, farm_id, "media", "upload", fingerprint):
                        raise ApiError(409, "mutation_conflict")
                    upload = session.scalar(
                        select(PhotoUpload)
                        .where(PhotoUpload.mutation_row_id == mutation.id)
                        .with_for_update()
                    )
                    if upload is None:
                        raise ApiError(409, "mutation_conflict")
                else:
                    if (
                        session.scalar(
                            select(Media.id).where(
                                Media.owner_id == owner,
                                Media.local_id == str(payload.local_media_id),
                            )
                        )
                        is not None
                    ):
                        raise ApiError(409, "mutation_conflict")
                    media_id = uuid4()
                    mutation = SyncMutation(
                        mutation_id=payload.mutation_id,
                        farm_id=farm_id,
                        owner_id=owner,
                        record_type="media",
                        operation="upload",
                        record_id=media_id,
                        request_fingerprint=fingerprint,
                    )
                    session.add(mutation)
                    session.flush()
                    upload = PhotoUpload(
                        farm_id=farm_id,
                        owner_id=owner,
                        section_id=payload.section_id,
                        mutation_row_id=mutation.id,
                        media_id=media_id,
                        local_media_id=payload.local_media_id,
                        content_type=payload.content_type,
                        byte_length=payload.byte_length,
                    )
                    session.add(upload)
                    session.flush()
                    self._new_attempt(session, upload)
                attempt = current_attempt(session, upload, lock=True)
                now = db_now(session)
                if upload.state == "awaiting_upload" and utc(attempt.expires_at) <= now:
                    upload.state = "expired"
                    attempt.terminal_at = now
                if upload.state == "expired":
                    upload.sequence += 1
                    upload.state = "awaiting_upload"
                    attempt = self._new_attempt(session, upload)
                if upload.state == "awaiting_upload":
                    # PostgreSQL now() is transaction-start time: a request
                    # acquiring the lock later can have an earlier timestamp.
                    # Never forget the lifetime of credentials already issued.
                    attempt.form_expires_at = max(
                        utc(attempt.form_expires_at), now + timedelta(minutes=5)
                    )
                    attempt.expires_at = max(utc(attempt.expires_at), now + timedelta(hours=1))
                return upload_view(session, upload), upload, attempt
        except IntegrityError:
            raise ApiError(409, "mutation_conflict") from None

    @staticmethod
    def _new_attempt(session: Session, upload: PhotoUpload) -> PhotoAttempt:
        now = db_now(session)
        attempt = PhotoAttempt(
            upload_id=upload.id,
            sequence=upload.sequence,
            expires_at=now + timedelta(hours=1),
            form_expires_at=now + timedelta(minutes=5),
            next_attempt_at=now,
        )
        session.add(attempt)
        session.flush()
        return attempt

    def retry_upload(
        self, authorization: str | None, farm_id: UUID, upload_id: UUID, failed_attempt_id: UUID
    ) -> UploadView:
        self.photo_rate(authorization)
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            farm_scope(session, owner, farm_id, lock=True)
            upload = session.scalar(
                select(PhotoUpload).where(
                    PhotoUpload.id == upload_id,
                    PhotoUpload.owner_id == owner,
                    PhotoUpload.farm_id == farm_id,
                )
            )
            if upload is None:
                raise ApiError(404, "not_found")
            section_scope(session, owner, farm_id, upload.section_id, lock=True)
            session.refresh(upload, with_for_update=True)
            attempt = current_attempt(session, upload, lock=True)
            previous = session.scalar(
                select(PhotoAttempt).where(
                    PhotoAttempt.id == failed_attempt_id, PhotoAttempt.upload_id == upload.id
                )
            )
            if previous is None:
                raise ApiError(404, "not_found")
            if previous.sequence < attempt.sequence:
                # Lost response or delayed duplicate: report current state, never
                # replenish the successor's budget, even if it has also failed.
                return upload_view(session, upload)
            if upload.state != "failed" or upload.error_code not in RECOVERABLE_ERRORS:
                raise ApiError(409, "upload_state_conflict")
            upload.sequence += 1
            upload.state, upload.error_code = "awaiting_upload", None
            self._new_attempt(session, upload)
            return upload_view(session, upload)

    def upload(
        self,
        authorization: str | None,
        farm_id: UUID,
        upload_id: UUID,
        *,
        complete: bool = False,
        expected_attempt: UUID | None = None,
    ) -> UploadView:
        if complete:
            self.photo_rate(authorization)
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            farm_scope(session, owner, farm_id, lock=complete)
            upload = session.scalar(
                select(PhotoUpload).where(
                    PhotoUpload.id == upload_id,
                    PhotoUpload.owner_id == owner,
                    PhotoUpload.farm_id == farm_id,
                )
            )
            if upload is None:
                raise ApiError(404, "not_found")
            section_scope(session, owner, farm_id, upload.section_id, lock=complete)
            # Parent locks serialize writes; read/status does not mutate state.
            attempt = current_attempt(session, upload)
            now = db_now(session)
            view = upload_view(session, upload)
            if expected_attempt is not None and (
                attempt.id != expected_attempt
                or upload.state != "awaiting_upload"
                or utc(attempt.form_expires_at) <= now
            ):
                raise ApiError(409, "upload_state_changed")
            if upload.state == "awaiting_upload" and utc(attempt.expires_at) <= now:
                view.state = "expired"
            if complete:
                if view.state in ("failed", "expired"):
                    raise ApiError(409, "upload_state_conflict")
                if upload.state == "awaiting_upload":
                    upload.state = "queued"
                    attempt.next_attempt_at = now
                    view.state = "queued"
            return view
