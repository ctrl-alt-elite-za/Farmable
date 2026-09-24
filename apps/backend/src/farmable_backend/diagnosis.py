"""Durable focus-photo submissions and fenced publication; no provider I/O in locks."""

import hashlib
from contextlib import contextmanager
from datetime import timedelta
from uuid import uuid4

from sqlalchemy import func, or_, select
from sqlalchemy.exc import IntegrityError

from farmable_backend.diagnosis_schemas import NOTICE_VERSION, DiagnosisView
from farmable_backend.gcs_photos import clean_key
from farmable_backend.models import (
    AuthIdentity,
    CropDiagnosis,
    Farm,
    Media,
    PhotoAttempt,
    PhotoUpload,
    Planting,
    Section,
    User,
)
from farmable_backend.record_access import (
    ApiError,
    authenticate,
    db_now,
    farm_scope,
    section_scope,
    utc,
)

# Farmable's cost-backed crops that are actually in Kindwise's public catalogue.
# Cabbage/spinach must not be sent and then portrayed as supported diagnoses.
SUPPORTED = {
    "tomato": "tomato",
    "tomatoes": "tomato",
    "onion": "onion",
    "onions": "onion",
    "potato": "potato",
    "potatoes": "potato",
}
LEASE_SECONDS = 180


class DiagnosisStore:
    def __init__(self, sessions):
        self.sessions = sessions

    @staticmethod
    def inputs(session, owner, farm, section, media_id, planting_id, *, lock=False):
        def scoped(model, key):
            query = select(model).where(
                model.id == key,
                model.owner_id == owner,
                model.farm_id == farm,
                model.section_id == section,
                model.deleted_at.is_(None),
            )
            return session.scalar(query.with_for_update() if lock else query)

        planting = scoped(Planting, planting_id)
        media = scoped(Media, media_id)
        if planting is None or media is None:
            raise ApiError(404, "not_found")
        upload = session.scalar(
            select(PhotoUpload).where(
                PhotoUpload.media_id == media.id,
                PhotoUpload.owner_id == owner,
                PhotoUpload.farm_id == farm,
                PhotoUpload.section_id == section,
                PhotoUpload.state == "ready",
            )
        )
        attempt = (
            None
            if upload is None
            else session.scalar(
                select(PhotoAttempt).where(
                    PhotoAttempt.upload_id == upload.id,
                    PhotoAttempt.sequence == upload.sequence,
                )
            )
        )
        if (
            upload is None
            or attempt is None
            or not attempt.clean_generation
            or not attempt.clean_sha256
            or media.object_key != clean_key(upload, attempt)
        ):
            raise ApiError(409, "diagnosis_photo_not_ready")
        return planting, media, upload, attempt

    def submit(self, auth, farm, section, payload):
        digest = hashlib.sha256(payload.model_dump_json().encode()).hexdigest()
        try:
            with self.sessions.begin() as session:
                owner = authenticate(session, auth)
                farm_scope(session, owner, farm, lock=True)
                section_scope(session, owner, farm, section, lock=True)
                # Same farm-before-user lock order as photo submissions. This
                # serializes per-owner quotas across farms without remote I/O.
                session.scalar(select(User).where(User.id == owner).with_for_update())
                existing = session.get(CropDiagnosis, payload.id)
                if existing is not None:
                    if (
                        existing.owner_id != owner
                        or existing.farm_id != farm
                        or existing.section_id != section
                        or existing.fingerprint != digest
                    ):
                        raise ApiError(409, "diagnosis_id_conflict")
                    return DiagnosisView.model_validate(existing)
                planting, _media, _upload, _attempt = self.inputs(
                    session, owner, farm, section, payload.media_id, payload.planting_id, lock=True
                )
                now = db_now(session)
                count = session.scalar(
                    select(func.count())
                    .select_from(CropDiagnosis)
                    .where(
                        CropDiagnosis.owner_id == owner,
                        CropDiagnosis.created_at > now - timedelta(days=1),
                    )
                )
                pending = session.scalar(
                    select(func.count())
                    .select_from(CropDiagnosis)
                    .where(
                        CropDiagnosis.owner_id == owner,
                        CropDiagnosis.state.in_(("queued", "processing")),
                    )
                )
                if count >= 20 or pending >= 4:
                    raise ApiError(429, "diagnosis_limit", 60)
                crop = SUPPORTED.get(planting.crop.strip().lower())
                record = CropDiagnosis(
                    id=payload.id,
                    owner_id=owner,
                    farm_id=farm,
                    section_id=section,
                    media_id=payload.media_id,
                    planting_id=planting.id,
                    planting_version=planting.version,
                    crop=crop or planting.crop,
                    fingerprint=digest,
                    consent_notice_version=payload.consent_notice_version,
                    state="queued" if crop else "unavailable",
                    attempts=0,
                    error=None if crop else "unsupported_crop",
                    result=None,
                    next_attempt_at=now,
                    created_at=now,
                    updated_at=now,
                )
                session.add(record)
                session.flush()
                return DiagnosisView.model_validate(record)
        except IntegrityError:
            raise ApiError(409, "diagnosis_id_conflict") from None

    def read(self, auth, farm, record_id=None, *, cancel=False, cursor=None, limit=50):
        with self.sessions.begin() as session:
            owner = authenticate(session, auth)
            farm_scope(session, owner, farm, lock=True)
            query = select(CropDiagnosis).where(
                CropDiagnosis.owner_id == owner, CropDiagnosis.farm_id == farm
            )
            if record_id is None:
                if cursor is not None:
                    query = query.where(CropDiagnosis.id > cursor)
                rows = list(session.scalars(query.order_by(CropDiagnosis.id).limit(limit + 1)))
                return {
                    "items": [DiagnosisView.model_validate(row) for row in rows[:limit]],
                    "next_cursor": rows[limit - 1].id if len(rows) > limit else None,
                }
            row = session.scalar(query.where(CropDiagnosis.id == record_id).with_for_update())
            if row is None:
                raise ApiError(404, "not_found")
            if cancel:
                row.state, row.result, row.error = "cancelled", None, None
                row.withdrawn_at = row.withdrawn_at or db_now(session)
                row.updated_at = db_now(session)
                row.lease_token, row.lease_expires_at = None, None
            return DiagnosisView.model_validate(row)

    @contextmanager
    def locked(self, record_id):
        with self.sessions.begin() as session:
            initial = session.get(CropDiagnosis, record_id)
            if initial is None:
                yield session, None
                return
            session.scalar(select(Farm).where(Farm.id == initial.farm_id).with_for_update())
            session.scalar(
                select(Section).where(Section.id == initial.section_id).with_for_update()
            )
            row = session.scalar(
                select(CropDiagnosis)
                .where(CropDiagnosis.id == record_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )
            yield session, row

    def active_inputs(self, session, row):
        if session.get(AuthIdentity, row.owner_id) is None or row.withdrawn_at is not None:
            raise ApiError(404, "scope_unavailable")
        farm_scope(session, row.owner_id, row.farm_id)
        section_scope(session, row.owner_id, row.farm_id, row.section_id)
        result = self.inputs(
            session,
            row.owner_id,
            row.farm_id,
            row.section_id,
            row.media_id,
            row.planting_id,
            lock=True,
        )
        if (
            result[0].version != row.planting_version
            or SUPPORTED.get(result[0].crop.strip().lower()) != row.crop
        ):
            raise ApiError(409, "scope_changed")
        return result

    @staticmethod
    def terminal(row, now, code):
        row.state, row.error, row.result = "unavailable", code, None
        row.lease_token, row.lease_expires_at, row.updated_at = None, None, now

    def candidates(self):
        with self.sessions() as session:
            now = db_now(session)
            return list(
                session.scalars(
                    select(CropDiagnosis.id)
                    .where(
                        or_(
                            (CropDiagnosis.state == "queued")
                            & (CropDiagnosis.next_attempt_at <= now),
                            (CropDiagnosis.state == "processing")
                            & (CropDiagnosis.lease_expires_at <= now),
                        )
                    )
                    .order_by(CropDiagnosis.next_attempt_at, CropDiagnosis.id)
                    .limit(50)
                )
            )

    def claim(self, record_id):
        with self.locked(record_id) as (session, row):
            if row is None or row.state not in {"queued", "processing"}:
                return None
            now = db_now(session)
            if row.state == "processing":
                if utc(row.lease_expires_at) <= now:
                    # Crash after a paid POST may already have incurred a charge.
                    # Never silently issue it again without provider idempotency.
                    self.terminal(row, now, "delivery_unknown")
                return None
            if utc(row.next_attempt_at) > now:
                return None
            if row.attempts >= 3 or utc(row.created_at) <= now - timedelta(days=1):
                self.terminal(row, now, "retry_exhausted")
                return None
            try:
                _planting, _media, upload, attempt = self.active_inputs(session, row)
            except ApiError:
                self.terminal(row, now, "scope_unavailable")
                return None
            if row.consent_notice_version != NOTICE_VERSION:
                self.terminal(row, now, "consent_required")
                return None
            row.state, row.lease_token = "processing", uuid4()
            row.attempts += 1
            row.updated_at = now
            row.lease_expires_at = now + timedelta(seconds=LEASE_SECONDS)
            return row, upload, attempt

    def authorized(self, record_id, token):
        with self.locked(record_id) as (session, row):
            if not self.owns(row, token, db_now(session)):
                return False
            try:
                self.active_inputs(session, row)
            except ApiError:
                return False
            return True

    @staticmethod
    def owns(row, token, now):
        return bool(
            row is not None
            and row.state == "processing"
            and row.lease_token == token
            and row.lease_expires_at is not None
            and utc(row.lease_expires_at) > now
        )

    def finish(self, record_id, token, *, result=None, error=None, retry=False):
        with self.locked(record_id) as (session, row):
            now = db_now(session)
            if not self.owns(row, token, now):
                return False
            try:
                self.active_inputs(session, row)
            except ApiError:
                self.terminal(row, now, "scope_unavailable")
                return False
            self.terminal(row, now, error)
            if result is not None:
                row.state, row.result = "ready", result.model_dump(mode="json")
            elif retry and row.attempts < 3:
                row.state = "queued"
                row.next_attempt_at = now + timedelta(seconds=30 * row.attempts)
            return True
