"""Ownership checks shared by HTTP transactions and background publication."""

import hashlib
import re
from datetime import UTC, datetime, timedelta
from uuid import UUID

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from farmable_backend.models import AuthIdentity, AuthSession, Farm, Section

ACCESS_TOKEN_TTL = timedelta(minutes=15)


class ApiError(Exception):
    def __init__(self, status: int, code: str, retry_after: int | None = None):
        self.status = status
        self.code = code
        self.retry_after = retry_after
        super().__init__(code)


def utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def db_now(session: Session) -> datetime:
    return utc(session.execute(select(func.now())).scalar_one())


def authenticate(session: Session, authorization: str | None) -> UUID:
    if not authorization or not re.fullmatch(r"(?i:Bearer) [A-Za-z0-9_-]{43}", authorization):
        raise ApiError(401, "invalid_session")
    digest = hashlib.sha256(authorization[7:].encode()).hexdigest()
    auth_session = session.scalar(
        select(AuthSession)
        .join(AuthIdentity, AuthSession.user_id == AuthIdentity.id)
        .where(
            AuthSession.access_token_hash == digest,
            AuthSession.revoked_at.is_(None),
            AuthSession.expires_at > func.now(),
            AuthIdentity.phone_verified.is_(True),
            AuthIdentity.email_verified.is_(True),
        )
    )
    if auth_session is None or utc(auth_session.created_at) + ACCESS_TOKEN_TTL <= datetime.now(UTC):
        raise ApiError(401, "invalid_session")
    return auth_session.user_id


def farm_scope(session: Session, owner: UUID, farm: UUID, *, lock: bool = False) -> Farm:
    query = select(Farm).where(Farm.id == farm, Farm.owner_id == owner, Farm.deleted_at.is_(None))
    record = session.scalar(
        query.with_for_update().execution_options(populate_existing=True) if lock else query
    )
    if record is None:
        raise ApiError(404, "not_found")
    return record


def section_scope(
    session: Session, owner: UUID, farm: UUID, section: UUID, *, lock: bool = False
) -> Section:
    query = select(Section).where(
        Section.id == section,
        Section.owner_id == owner,
        Section.farm_id == farm,
        Section.deleted_at.is_(None),
    )
    record = session.scalar(
        query.with_for_update().execution_options(populate_existing=True) if lock else query
    )
    if record is None:
        raise ApiError(404, "not_found")
    return record
