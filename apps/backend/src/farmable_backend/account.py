"""Account, privacy and session-revocation service.

Owner scope always comes from the authenticated session, never from a caller
parameter. Responses and exports carry no password, OTP or token material.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import io
import json
import secrets
import zipfile
from datetime import UTC, date, datetime, timedelta
from decimal import Decimal
from typing import Any, cast
from uuid import UUID, uuid4

from argon2.exceptions import InvalidHashError, VerificationError
from sqlalchemy import delete, select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.account_schemas import (
    AccountFarmResponse,
    FarmUpdate,
    Language,
    ProfileResponse,
    ProfileUpdate,
)
from farmable_backend.auth import (
    OTP_TTL,
    PASSWORD_HASHER,
    Channel,
    DisabledOtpProvider,
    OtpProvider,
    check_sms_limits,
)
from farmable_backend.auth import AuthError as _AuthError
from farmable_backend.idempotency import (
    IdempotencyConflict,
    IdempotencyInProgress,
)
from farmable_backend.idempotency import (
    abandon as idempotency_abandon,
)
from farmable_backend.idempotency import (
    claim as idempotency_claim,
)
from farmable_backend.idempotency import (
    store as idempotency_store,
)
from farmable_backend.models import (
    DEFAULT_ACCOUNT_LANGUAGE,
    AccountProfile,
    AuthIdentity,
    AuthSession,
    Consent,
    ExportJob,
    Farm,
    FarmLocation,
    FarmTask,
    FinancialRecord,
    Media,
    Observation,
    PendingContactChange,
    PhotoAttempt,
    PhotoUpload,
    Planting,
    SavedPlan,
    Section,
    SyncMutation,
    User,
    VerificationChallenge,
)
from farmable_backend.rate_limits import RateLimited
from farmable_backend.rate_limits import check as rate_limit_check
from farmable_backend.record_access import ApiError, authenticate

EXPORT_SCHEMA_VERSION = 1
EXPORT_BASENAME = "farmable-export"
EXPORT_ENTRY_NAME = "export.json"
EXPORT_JOB_TTL = timedelta(hours=24)
EXPORT_JOB_RATE_WINDOW_SECONDS = 3600
EXPORT_JOB_RATE_LIMIT = 5
EXPORT_CONSENT_TYPE = "data_export"
EXPORT_CONSENT_VERSION = "1"
# A fixed entry timestamp keeps the archive byte-for-byte reproducible.
EXPORT_ZIP_TIMESTAMP = (1980, 1, 1, 0, 0, 0)
# Owner-scoped record tables, in export order. auth_identities,
# verification_challenges and auth_sessions are deliberately absent: password
# hashes, OTP hashes and token hashes must never reach an export.
EXPORTED_RECORDS: tuple[tuple[str, Any], ...] = (
    ("farms", Farm),
    ("sections", Section),
    ("plantings", Planting),
    ("media", Media),
    ("observations", Observation),
    ("tasks", FarmTask),
    ("financial_records", FinancialRecord),
    ("saved_plans", SavedPlan),
    ("sync_mutations", SyncMutation),
)


def _value(value: Any) -> Any:
    if isinstance(value, UUID):
        return str(value)
    if isinstance(value, datetime | date):
        return value.isoformat()
    if isinstance(value, Decimal):
        return str(value)
    return value


def _row(record: Any) -> dict[str, Any]:
    columns = sorted(type(record).__table__.columns.keys())
    return {name: _value(getattr(record, name)) for name in columns}


def _verify_password(password_hash: str, password: str) -> bool:
    try:
        return PASSWORD_HASHER.verify(password_hash, password)
    except (VerificationError, InvalidHashError):
        return False


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _bearer_digest(authorization: str | None) -> str:
    if authorization is None:
        raise ApiError(401, "invalid_session")
    return hashlib.sha256(authorization[7:].encode()).hexdigest()


def json_bytes(document: dict[str, Any]) -> bytes:
    return (json.dumps(document, indent=2, sort_keys=True) + "\n").encode("utf-8")


def zip_bytes(document: dict[str, Any]) -> bytes:
    buffer = io.BytesIO()
    entry = zipfile.ZipInfo(EXPORT_ENTRY_NAME, EXPORT_ZIP_TIMESTAMP)
    entry.compress_type = zipfile.ZIP_DEFLATED
    entry.external_attr = 0o600 << 16
    with zipfile.ZipFile(buffer, "w") as archive:
        archive.writestr(entry, json_bytes(document))
    return buffer.getvalue()


class AccountService:
    def __init__(
        self,
        sessions: sessionmaker[Session],
        provider: OtpProvider | None = None,
        export_token_secret: str | None = None,
    ):
        self.sessions = sessions
        self.provider = provider or DisabledOtpProvider()
        # Production supplies a stable dedicated secret through Settings. The
        # generated fallback keeps isolated/test services usable without ever
        # deriving bearer credentials from the database URL.
        self._export_token_secret = export_token_secret or secrets.token_urlsafe(32)

    def owner_id(self, authorization: str | None) -> UUID:
        with self.sessions.begin() as session:
            return authenticate(session, authorization)

    def profile(self, authorization: str | None) -> ProfileResponse:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            return self._profile(session, self._identity(session, owner))

    def update_profile(
        self,
        authorization: str | None,
        payload: ProfileUpdate,
        *,
        ip: str = "unknown",
        idempotency_key: str | None = None,
        idempotency_scope: str = "",
        request_fingerprint: str | None = None,
    ) -> ProfileResponse:
        if idempotency_key is not None:
            if request_fingerprint is None:
                raise ApiError(400, "idempotency_key_required")
            try:
                replayed = idempotency_claim(
                    self.sessions,
                    route="account_profile",
                    scope=idempotency_scope,
                    key=idempotency_key,
                    request_fingerprint=request_fingerprint,
                )
            except IdempotencyConflict:
                raise ApiError(409, "idempotency_key_conflict") from None
            except IdempotencyInProgress:
                raise ApiError(409, "idempotency_in_progress", 1) from None
            if replayed is not None:
                status, body = replayed
                if status >= 400:
                    error = body.get("error", {})
                    raise ApiError(
                        status,
                        error.get("code", "request_failed"),
                        error.get("retry_after"),
                    )
                return ProfileResponse(**body)
        contact_started = False
        try:
            with self.sessions.begin() as session:
                owner = authenticate(session, authorization)
                identity = self._identity(session, owner)
                if payload.first_name is not None:
                    identity.first_name = payload.first_name.strip()
                if payload.surname is not None:
                    identity.surname = payload.surname.strip()
                if payload.preferred_language is not None:
                    self._set_language(session, owner, payload.preferred_language)
                session.flush()
                response = self._profile(session, identity)
            # Email/phone changes never apply inline: they only ever take effect
            # through confirm_contact_change, after the destination proves control
            # by returning the OTP it received. Requested after the main profile
            # transaction commits so a request that changes name+email still
            # persists the name even if the OTP send fails.
            if payload.email is not None:
                contact_started = True
                if idempotency_key is not None:
                    idempotency_store(
                        self.sessions,
                        route="account_profile",
                        scope=idempotency_scope,
                        key=idempotency_key,
                        request_fingerprint=request_fingerprint,
                        status_code=503,
                        body={"error": {"code": "delivery_unknown"}},
                    )
                self._request_contact_change(
                    authorization, Channel.EMAIL, payload.email, idempotency_key=idempotency_key
                )
            if payload.phone is not None:
                contact_started = True
                if idempotency_key is not None:
                    idempotency_store(
                        self.sessions,
                        route="account_profile",
                        scope=idempotency_scope,
                        key=idempotency_key,
                        request_fingerprint=request_fingerprint,
                        status_code=503,
                        body={"error": {"code": "delivery_unknown"}},
                    )
                self._request_contact_change(
                    authorization,
                    Channel.PHONE,
                    payload.phone,
                    ip=ip,
                    idempotency_key=idempotency_key,
                )
            if payload.email is not None or payload.phone is not None:
                with self.sessions.begin() as session:
                    owner = authenticate(session, authorization)
                    response = self._profile(session, self._identity(session, owner))
            if idempotency_key is not None:
                idempotency_store(
                    self.sessions,
                    route="account_profile",
                    scope=idempotency_scope,
                    key=idempotency_key,
                    request_fingerprint=request_fingerprint,
                    status_code=200,
                    body=response.model_dump(mode="json"),
                    overwrite=True,
                )
            return response
        except Exception as exc:
            if idempotency_key is not None:
                if contact_started and isinstance(exc, ApiError):
                    idempotency_store(
                        self.sessions,
                        route="account_profile",
                        scope=idempotency_scope,
                        key=idempotency_key,
                        request_fingerprint=request_fingerprint,
                        status_code=exc.status,
                        body={
                            "error": {
                                "code": exc.code,
                                "retry_after": exc.retry_after,
                            }
                        },
                        overwrite=True,
                    )
                else:
                    idempotency_abandon(
                        self.sessions,
                        route="account_profile",
                        scope=idempotency_scope,
                        key=idempotency_key,
                    )
            raise

    def confirm_contact_change(
        self, authorization: str | None, channel: Channel, code: str
    ) -> ProfileResponse:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            identity = session.scalar(
                select(AuthIdentity).where(AuthIdentity.id == owner).with_for_update()
            )
            if identity is None:
                raise ApiError(401, "invalid_session")
            pending_row = session.scalar(
                select(PendingContactChange)
                .where(PendingContactChange.user_id == owner)
                .with_for_update()
            )
            if pending_row is None:
                raise ApiError(400, "no_pending_change")
            pending = (
                pending_row.pending_email if channel is Channel.EMAIL else pending_row.pending_phone
            )
            if pending is None:
                raise ApiError(400, "no_pending_change")
            challenge = session.scalar(
                select(VerificationChallenge)
                .where(
                    VerificationChallenge.user_id == owner,
                    VerificationChallenge.channel == channel.value,
                    VerificationChallenge.consumed_at.is_(None),
                )
                .order_by(VerificationChallenge.created_at.desc())
                .with_for_update()
            )
            if (
                challenge is None
                or _as_utc(challenge.expires_at) <= datetime.now(UTC)
                or challenge.attempts >= 5
            ):
                raise ApiError(400, "invalid_verification")
            if not self._verify_code(challenge.code_hash, code):
                challenge.attempts += 1
                failure = ApiError(400, "invalid_verification")
            else:
                failure = None
            if failure is not None:
                # Leave the transaction normally so the failed-attempt counter
                # commits before the API error is raised.
                pass
            else:
                challenge.consumed_at = datetime.now(UTC)
                try:
                    with session.begin_nested():
                        if channel is Channel.EMAIL:
                            identity.email = pending
                            pending_row.pending_email = None
                        else:
                            identity.phone = pending
                            pending_row.pending_phone = None
                        session.flush()
                except IntegrityError:
                    raise ApiError(409, "contact_unavailable") from None
                response = self._profile(session, identity)
        if failure is not None:
            raise failure
        return response

    def _request_contact_change(
        self,
        authorization: str | None,
        channel: Channel,
        new_value: str,
        *,
        ip: str = "unknown",
        idempotency_key: str | None = None,
    ) -> None:
        normalized = new_value.strip().lower() if channel is Channel.EMAIL else new_value.strip()
        failure: ApiError | None = None
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            # Lock the parent identity row first so two concurrent first-use
            # pending-change writes serialize, as _set_language does for
            # account_profiles: without it, both could see no
            # pending_contact_changes row and the second insert would fail
            # the primary key with an unhandled 500.
            identity = session.scalar(
                select(AuthIdentity).where(AuthIdentity.id == owner).with_for_update()
            )
            if identity is None:
                raise ApiError(401, "invalid_session")
            current = identity.email if channel is Channel.EMAIL else identity.phone
            if normalized == current:
                return  # No-op: already the caller's own verified value.
            column = AuthIdentity.email if channel is Channel.EMAIL else AuthIdentity.phone
            collision = session.scalar(
                select(AuthIdentity.id).where(column == normalized, AuthIdentity.id != owner)
            )
            if collision is not None:
                # Enumeration-safe: identical to a fresh request either way.
                # Warn the real owner instead of confirming existence to the
                # caller, and never store a pending value that would collide.
                if channel is Channel.PHONE:
                    try:
                        check_sms_limits(self.sessions, ip=ip, phone=normalized)
                    except _AuthError as exc:
                        raise ApiError(exc.status_code, exc.code, exc.retry_after) from exc
                try:
                    self.provider.notify_existing_account(channel, normalized)
                except _AuthError:
                    pass
                return
            pending_row = session.get(PendingContactChange, owner)
            if pending_row is None:
                pending_row = PendingContactChange(user_id=owner)
                session.add(pending_row)
            if channel is Channel.EMAIL:
                pending_row.pending_email = normalized
            else:
                pending_row.pending_phone = normalized
                try:
                    check_sms_limits(self.sessions, ip=ip, phone=normalized)
                except _AuthError as exc:
                    raise ApiError(exc.status_code, exc.code, exc.retry_after) from exc
            session.execute(
                update(VerificationChallenge)
                .where(
                    VerificationChallenge.user_id == owner,
                    VerificationChallenge.channel == channel.value,
                    VerificationChallenge.consumed_at.is_(None),
                )
                .values(consumed_at=datetime.now(UTC))
            )
            code = self.provider.create_code(channel)
            try:
                if idempotency_key is not None and hasattr(type(self.provider), "deliver_with_key"):
                    cast(Any, self.provider).deliver_with_key(
                        channel, normalized, code, idempotency_key
                    )
                else:
                    self.provider.deliver(channel, normalized, code)
            except _AuthError as exc:
                if exc.code != "delivery_unknown":
                    raise ApiError(exc.status_code, exc.code, exc.retry_after) from exc
                failure = ApiError(exc.status_code, exc.code, exc.retry_after)
            session.add(
                VerificationChallenge(
                    user_id=owner,
                    channel=channel.value,
                    code_hash=PASSWORD_HASHER.hash(code),
                    expires_at=datetime.now(UTC) + OTP_TTL,
                )
            )
        if failure is not None:
            raise failure

    def farm(self, authorization: str | None) -> AccountFarmResponse:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            return self._farm_response(session, self._farm(session, owner))

    def update_farm(self, authorization: str | None, payload: FarmUpdate) -> AccountFarmResponse:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            record = self._farm(session, owner, lock=True)
            if payload.name is not None:
                record.name = payload.name.strip()
            if payload.preferred_language is not None:
                self._set_language(session, owner, payload.preferred_language)
            if payload.latitude is not None or payload.longitude is not None:
                self._set_location(session, record.id, payload.latitude, payload.longitude)
            session.flush()
            return self._farm_response(session, record)

    def export_document(self, authorization: str | None) -> dict[str, Any]:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            self._require_export_consent(session, owner)
            return self._export_document_for(session, owner)

    def create_export_job(
        self,
        authorization: str | None,
        format: str,
        *,
        idempotency_key: str | None = None,
        idempotency_scope: str = "",
        request_fingerprint: str | None = None,
    ) -> tuple[UUID, str]:
        """Create (or, on request-collapse, reuse) an export job.

        Rate-limited per account, in its own short transaction, before any
        other work — a rejected request builds no artifact. The raw download
        token is returned only here, once; only its hash is ever persisted.
        """
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            session.execute(
                select(AuthIdentity).where(AuthIdentity.id == owner).with_for_update()
            ).scalar_one()
            self._require_export_consent(session, owner)
        if idempotency_key is not None:
            try:
                replayed = idempotency_claim(
                    self.sessions,
                    route="account_export_job_create",
                    scope=idempotency_scope,
                    key=idempotency_key,
                    request_fingerprint=request_fingerprint or "",
                )
            except IdempotencyConflict:
                raise ApiError(409, "idempotency_key_conflict") from None
            except IdempotencyInProgress:
                raise ApiError(409, "idempotency_in_progress", 1) from None
            if replayed is not None:
                _status, body = replayed
                return UUID(body["id"]), self._export_token(UUID(body["id"]))
        try:
            try:
                rate_limit_check(
                    self.sessions,
                    scope="export_job",
                    subject=str(owner),
                    window_seconds=EXPORT_JOB_RATE_WINDOW_SECONDS,
                    limit=EXPORT_JOB_RATE_LIMIT,
                    code="export_rate_limited",
                )
            except RateLimited as exc:
                raise ApiError(429, exc.code, exc.retry_after) from None
            with self.sessions.begin() as session:
                document = self._export_document_for(session, owner)
                job_id = uuid4()
                token = self._export_token(job_id)
                job = ExportJob(
                    owner_id=owner,
                    status="ready",
                    format=format,
                    artifact=zip_bytes(document) if format == "zip" else json_bytes(document),
                    id=job_id,
                    download_token_hash=hashlib.sha256(token.encode()).hexdigest(),
                    expires_at=datetime.now(UTC) + EXPORT_JOB_TTL,
                )
                session.add(job)
            if idempotency_key is not None:
                idempotency_store(
                    self.sessions,
                    route="account_export_job_create",
                    scope=idempotency_scope,
                    key=idempotency_key,
                    request_fingerprint=request_fingerprint or "",
                    status_code=201,
                    body={"id": str(job_id)},
                )
            return job_id, token
        except Exception:
            if idempotency_key is not None:
                idempotency_abandon(
                    self.sessions,
                    route="account_export_job_create",
                    scope=idempotency_scope,
                    key=idempotency_key,
                )
            raise

    def _export_token(self, job_id: UUID) -> str:
        digest = hmac.new(
            self._export_token_secret.encode(),
            b"farmable-export-token:" + job_id.bytes,
            hashlib.sha256,
        ).digest()
        return base64.urlsafe_b64encode(digest).decode().rstrip("=")

    @staticmethod
    def _require_export_consent(session: Session, owner: UUID) -> None:
        consent = session.scalar(
            select(Consent).where(
                Consent.user_id == owner,
                Consent.consent_type == EXPORT_CONSENT_TYPE,
                Consent.version == EXPORT_CONSENT_VERSION,
            )
        )
        if consent is None or consent.granted_at is None or consent.withdrawn_at is not None:
            raise ApiError(403, "consent_required")

    def export_job_status(self, authorization: str | None, job_id: UUID) -> dict[str, Any]:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            job = self._owned_export_job(session, owner, job_id)
            return {
                "id": str(job.id),
                "status": job.status,
                "format": job.format,
                "created_at": _value(job.created_at),
                "expires_at": _value(job.expires_at),
            }

    def download_export_job(self, job_id: UUID, token: str) -> tuple[bytes, str]:
        """Authorize solely by the possession of ``token`` (a bearer session
        is never required here, matching the issue's "authorized download
        link" — the link itself is the credential, short-lived and
        single-purpose). An already-downloaded or expired job is treated the
        same as an unknown one: no information about its existence leaks."""
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        with self.sessions.begin() as session:
            job = session.scalar(
                select(ExportJob)
                .where(ExportJob.id == job_id, ExportJob.download_token_hash == token_hash)
                .with_for_update()
            )
            if (
                job is None
                or job.status != "ready"
                or job.downloaded_at is not None
                or job.artifact is None
                or job.expires_at is None
                or _as_utc(job.expires_at) < datetime.now(UTC)
            ):
                raise ApiError(404, "export_not_found")
            artifact, media_type = (
                job.artifact,
                ("application/zip" if job.format == "zip" else "application/json"),
            )
            job.downloaded_at = datetime.now(UTC)
            return artifact, media_type

    def cleanup_expired_export_jobs(self, *, limit: int = 200) -> int:
        """Bounded, retryable sweep: clears artifacts/tokens past expiry so
        storage does not grow unboundedly. Safe to call repeatedly/concurrently
        — each row transitions at most once (``status == "ready"`` guards it)."""
        now = datetime.now(UTC)
        cleared = 0
        with self.sessions.begin() as session:
            jobs = session.scalars(
                select(ExportJob)
                .where(ExportJob.status == "ready", ExportJob.expires_at < now)
                .order_by(ExportJob.expires_at)
                .limit(limit)
                .with_for_update(skip_locked=True)
            ).all()
            for job in jobs:
                job.status = "expired"
                job.artifact = None
                job.download_token_hash = None
                cleared += 1
        return cleared

    def _export_document_for(self, session: Session, owner: UUID) -> dict[str, Any]:
        identity = self._identity(session, owner)
        document: dict[str, Any] = {
            "schema_version": EXPORT_SCHEMA_VERSION,
            "account": {
                "id": str(identity.id),
                "first_name": identity.first_name,
                "surname": identity.surname,
                "phone": identity.phone,
                "email": identity.email,
                "phone_verified": identity.phone_verified,
                "email_verified": identity.email_verified,
                "preferred_language": self._language(session, owner),
                "created_at": _value(identity.created_at),
            },
        }
        for name, model in EXPORTED_RECORDS:
            rows = session.scalars(
                select(model).where(model.owner_id == owner).order_by(model.id)
            ).all()
            document[name] = [_row(row) for row in rows]
        return document

    @staticmethod
    def _owned_export_job(session: Session, owner: UUID, job_id: UUID) -> ExportJob:
        job = session.get(ExportJob, job_id)
        if job is None or job.owner_id != owner:
            raise ApiError(404, "export_not_found")
        return job

    def logout(self, authorization: str | None) -> None:
        digest = _bearer_digest(authorization)
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            session.execute(
                update(AuthSession)
                .where(
                    AuthSession.user_id == owner,
                    AuthSession.access_token_hash == digest,
                    AuthSession.revoked_at.is_(None),
                )
                .values(revoked_at=datetime.now(UTC))
            )

    def list_consents(self, authorization: str | None) -> list[dict[str, Any]]:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            rows = session.scalars(
                select(Consent)
                .where(Consent.user_id == owner)
                .order_by(Consent.consent_type, Consent.version)
            ).all()
            return [
                {
                    "consent_type": row.consent_type,
                    "version": row.version,
                    "granted": row.granted_at is not None and row.withdrawn_at is None,
                    "granted_at": _value(row.granted_at),
                    "withdrawn_at": _value(row.withdrawn_at),
                    "source": row.source,
                }
                for row in rows
            ]

    def set_consent(
        self, authorization: str | None, consent_type: str, version: str, granted: bool
    ) -> dict[str, Any]:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            now = datetime.now(UTC)
            row = session.scalar(
                select(Consent).where(
                    Consent.user_id == owner,
                    Consent.consent_type == consent_type,
                    Consent.version == version,
                )
            )
            if row is None:
                row = Consent(
                    user_id=owner,
                    consent_type=consent_type,
                    version=version,
                    granted_at=now if granted else None,
                    withdrawn_at=None if granted else now,
                )
                session.add(row)
            elif granted:
                row.granted_at = row.granted_at or now
                row.withdrawn_at = None
            else:
                row.withdrawn_at = now
            return {
                "consent_type": row.consent_type,
                "version": row.version,
                "granted": granted,
                "granted_at": _value(row.granted_at),
                "withdrawn_at": _value(row.withdrawn_at),
                "source": row.source,
            }

    def revoke_all(self, authorization: str | None) -> None:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            session.execute(
                update(AuthSession)
                .where(AuthSession.user_id == owner, AuthSession.revoked_at.is_(None))
                .values(revoked_at=datetime.now(UTC))
            )

    def delete_account(self, authorization: str | None, password: str) -> None:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            identity = self._identity(session, owner)
            if not _verify_password(identity.password_hash, password):
                raise ApiError(401, "invalid_credentials")
            now = datetime.now(UTC)
            # Deliberate deviation from the tombstone contract that
            # farm_records.tombstone_* follows (deleted_at + version bump +
            # sync_state="pending" + a SyncChange row). That contract exists to
            # publish a delete to the owner's other devices through /changes,
            # and here there is no reader left to publish to: every AuthSession
            # for this owner is hard-deleted a few lines below, in this same
            # transaction, and record_access.authenticate admits a caller only
            # against a live, unrevoked auth_sessions row. The account can never
            # be authenticated again, so nothing can ever pull this feed.
            # It is also structurally unavailable: SyncChange.mutation_id is NOT
            # NULL and foreign-keys to sync_mutations, so each change row needs a
            # real client-supplied, idempotency-keyed mutation. A server-initiated
            # bulk delete has none, and synthesising fake mutations to satisfy the
            # constraint would corrupt the replay-detection they exist for.
            # test_deletion_tombstones_without_publishing_sync_changes pins this.
            for _name, model in EXPORTED_RECORDS:
                if model is SyncMutation:
                    continue  # Immutable audit rows; they carry no deleted_at.
                session.execute(
                    update(model)
                    .where(model.owner_id == owner, model.deleted_at.is_(None))
                    .values(deleted_at=now)
                )
            # Explicit deletes rather than a users-row cascade: the ownership
            # row stays so every farm foreign key, photo upload and rate row
            # keeps its referent. The credential identity itself is removed.
            # Retain photo rows because they contain the only durable GCS object
            # keys, but make every attempt eligible for the janitor again. This
            # includes ready photos (whose clean object is normally preserved)
            # and attempts cleaned before deletion. Marking the upload failed
            # makes cleanup_claim return keep_clean=False; clearing cleaned_at
            # re-enqueues previously cleaned attempts. The normal one-hour
            # terminal grace period still protects in-flight external work.
            owned_uploads = select(PhotoUpload.id).where(PhotoUpload.owner_id == owner)
            session.execute(
                update(PhotoAttempt)
                .where(PhotoAttempt.upload_id.in_(owned_uploads))
                .values(
                    terminal_at=now,
                    cleaned_at=None,
                    cleanup_token=None,
                    cleanup_expires_at=None,
                    lease_token=None,
                    lease_expires_at=None,
                )
            )
            session.execute(
                update(PhotoUpload)
                .where(PhotoUpload.owner_id == owner)
                .values(state="failed", error_code="scope_unavailable")
            )
            session.execute(delete(AccountProfile).where(AccountProfile.user_id == owner))
            session.execute(
                delete(PendingContactChange).where(PendingContactChange.user_id == owner)
            )
            owned_farms = select(Farm.id).where(Farm.owner_id == owner)
            session.execute(delete(FarmLocation).where(FarmLocation.farm_id.in_(owned_farms)))
            # Export artifacts contain the same owner-scoped data as the rows
            # just tombstoned above; purge them outright rather than leaving
            # a still-downloadable copy of a deleted account's data.
            session.execute(delete(ExportJob).where(ExportJob.owner_id == owner))
            session.execute(delete(AuthSession).where(AuthSession.user_id == owner))
            session.execute(
                delete(VerificationChallenge).where(VerificationChallenge.user_id == owner)
            )
            session.delete(identity)

    @staticmethod
    def _identity(session: Session, owner: UUID) -> AuthIdentity:
        identity = session.get(AuthIdentity, owner)
        if identity is None:
            raise ApiError(401, "invalid_session")
        return identity

    @staticmethod
    def _farm(session: Session, owner: UUID, *, lock: bool = False) -> Farm:
        query = (
            select(Farm)
            .where(Farm.owner_id == owner, Farm.deleted_at.is_(None))
            .order_by(Farm.created_at, Farm.id)
            .limit(1)
        )
        record = session.scalar(query.with_for_update() if lock else query)
        if record is None:
            raise ApiError(404, "not_found")
        return record

    @staticmethod
    def _language(session: Session, owner: UUID) -> Language:
        profile = session.get(AccountProfile, owner)
        value = DEFAULT_ACCOUNT_LANGUAGE if profile is None else profile.preferred_language
        return cast(Language, value)

    @staticmethod
    def _set_language(session: Session, owner: UUID, language: Language) -> None:
        # Lock the existing owner row so concurrent first-use inserts are
        # serialized, as voice_api.admit and RecordsService.photo_rate do for
        # their own user-keyed get-or-insert tables. Without it two concurrent
        # first language writes both see no profile row and the second insert
        # fails the account_profiles primary key with an unhandled 500.
        session.scalar(select(User).where(User.id == owner).with_for_update())
        profile = session.get(AccountProfile, owner)
        if profile is None:
            session.add(AccountProfile(user_id=owner, preferred_language=language))
        else:
            profile.preferred_language = language

    @staticmethod
    def _set_location(
        session: Session, farm_id: UUID, latitude: float | None, longitude: float | None
    ) -> None:
        # Lock the parent farm row first, matching _set_language's get-or-insert
        # locking so two concurrent first-use writes cannot both miss and race
        # the farm_locations primary key.
        session.scalar(select(Farm).where(Farm.id == farm_id).with_for_update())
        location = session.get(FarmLocation, farm_id)
        if location is None:
            location = FarmLocation(farm_id=farm_id)
            session.add(location)
        if latitude is not None:
            location.latitude_tenths = round(latitude * 10)
        if longitude is not None:
            location.longitude_tenths = round(longitude * 10)

    @staticmethod
    def _location(session: Session, farm_id: UUID) -> tuple[float | None, float | None]:
        location = session.get(FarmLocation, farm_id)
        if location is None:
            return None, None
        lat = None if location.latitude_tenths is None else location.latitude_tenths / 10
        lon = None if location.longitude_tenths is None else location.longitude_tenths / 10
        return lat, lon

    def _profile(self, session: Session, identity: AuthIdentity) -> ProfileResponse:
        pending = session.get(PendingContactChange, identity.id)
        return ProfileResponse(
            id=identity.id,
            first_name=identity.first_name,
            surname=identity.surname,
            phone=identity.phone,
            email=identity.email,
            phone_verified=identity.phone_verified,
            email_verified=identity.email_verified,
            preferred_language=self._language(session, identity.id),
            pending_email=None if pending is None else pending.pending_email,
            pending_phone=None if pending is None else pending.pending_phone,
        )

    def _farm_response(self, session: Session, record: Farm) -> AccountFarmResponse:
        latitude, longitude = self._location(session, record.id)
        return AccountFarmResponse(
            id=record.id,
            owner_id=record.owner_id,
            name=record.name,
            preferred_language=self._language(session, record.owner_id),
            latitude=latitude,
            longitude=longitude,
        )

    @staticmethod
    def _verify_code(code_hash: str, code: str) -> bool:
        try:
            return PASSWORD_HASHER.verify(code_hash, code)
        except (VerificationError, InvalidHashError):
            return False
