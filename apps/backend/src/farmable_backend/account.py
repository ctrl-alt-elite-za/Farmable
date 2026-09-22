"""Account, privacy and session-revocation service.

Owner scope always comes from the authenticated session, never from a caller
parameter. Responses and exports carry no password, OTP or token material.
"""

from __future__ import annotations

import hashlib
import io
import json
import zipfile
from datetime import UTC, date, datetime
from decimal import Decimal
from typing import Any, cast
from uuid import UUID

from argon2.exceptions import InvalidHashError, VerificationError
from sqlalchemy import delete, select, update
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.account_schemas import (
    AccountFarmResponse,
    FarmUpdate,
    Language,
    ProfileResponse,
    ProfileUpdate,
)
from farmable_backend.auth import PASSWORD_HASHER
from farmable_backend.models import (
    DEFAULT_ACCOUNT_LANGUAGE,
    AccountProfile,
    AuthIdentity,
    AuthSession,
    Farm,
    FarmTask,
    FinancialRecord,
    Media,
    Observation,
    Planting,
    SavedPlan,
    Section,
    SyncMutation,
    VerificationChallenge,
)
from farmable_backend.record_access import ApiError, authenticate

EXPORT_SCHEMA_VERSION = 1
EXPORT_BASENAME = "farmable-export"
EXPORT_ENTRY_NAME = "export.json"
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
    def __init__(self, sessions: sessionmaker[Session]):
        self.sessions = sessions

    def profile(self, authorization: str | None) -> ProfileResponse:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
            return self._profile(session, self._identity(session, owner))

    def update_profile(self, authorization: str | None, payload: ProfileUpdate) -> ProfileResponse:
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
            return self._profile(session, identity)

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
            session.flush()
            return self._farm_response(session, record)

    def export_document(self, authorization: str | None) -> dict[str, Any]:
        with self.sessions.begin() as session:
            owner = authenticate(session, authorization)
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
            session.execute(delete(AccountProfile).where(AccountProfile.user_id == owner))
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
        profile = session.get(AccountProfile, owner)
        if profile is None:
            session.add(AccountProfile(user_id=owner, preferred_language=language))
        else:
            profile.preferred_language = language

    def _profile(self, session: Session, identity: AuthIdentity) -> ProfileResponse:
        return ProfileResponse(
            id=identity.id,
            first_name=identity.first_name,
            surname=identity.surname,
            phone=identity.phone,
            email=identity.email,
            phone_verified=identity.phone_verified,
            email_verified=identity.email_verified,
            preferred_language=self._language(session, identity.id),
        )

    def _farm_response(self, session: Session, record: Farm) -> AccountFarmResponse:
        return AccountFarmResponse(
            id=record.id,
            owner_id=record.owner_id,
            name=record.name,
            preferred_language=self._language(session, record.owner_id),
        )
