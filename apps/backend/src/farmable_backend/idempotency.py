"""Durable Idempotency-Key handling (#9).

A replay of the same key with the same request body returns the original
stored response without re-running the mutation. A replay with a different
body is rejected. Records are looked up/stored in their own short
transaction, independent of the mutation's own transaction, so a crash
between the mutation committing and the record being written falls back
safely on the mutation's own idempotent behavior (e.g. the unique
constraint on ``auth_identities.email``/``phone``) rather than corrupting
state.
"""

from __future__ import annotations

import hashlib
import json
from datetime import UTC, datetime, timedelta
from typing import Any
from uuid import UUID

from sqlalchemy import delete
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.models import IdempotencyRecord


class IdempotencyConflict(Exception):
    """Same key, different request body."""


class IdempotencyInProgress(Exception):
    """Another request currently owns this idempotency key."""


IN_PROGRESS_STATUS = 102
CLAIM_TIMEOUT = timedelta(minutes=5)


def fingerprint(payload: dict[str, Any]) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode()).hexdigest()


def replay(
    sessions: sessionmaker[Session], *, route: str, scope: str, key: str, request_fingerprint: str
) -> tuple[int, dict[str, Any]] | None:
    """Return the stored (status_code, body) for a prior identical request, if any."""
    with sessions.begin() as session:
        record = session.get(IdempotencyRecord, (route, scope, key))
        if record is None:
            return None
        if record.request_fingerprint != request_fingerprint:
            raise IdempotencyConflict
        if record.status_code == IN_PROGRESS_STATUS:
            raise IdempotencyInProgress
        return record.status_code, record.response_body


def claim(
    sessions: sessionmaker[Session],
    *,
    route: str,
    scope: str,
    key: str,
    request_fingerprint: str,
) -> tuple[int, dict[str, Any]] | None:
    """Atomically reserve a key before its mutation runs.

    ``None`` means this caller owns a new claim. A completed response is
    returned for a replay; a live claim is rejected rather than allowing two
    requests to perform the mutation concurrently.
    """
    identity = (route, scope, key)
    for _attempt in range(2):
        try:
            with sessions.begin() as session:
                session.add(
                    IdempotencyRecord(
                        route=route,
                        scope=scope,
                        idempotency_key=key,
                        request_fingerprint=request_fingerprint,
                        status_code=IN_PROGRESS_STATUS,
                        response_body={},
                    )
                )
                session.flush()
                return None
        except IntegrityError:
            with sessions.begin() as session:
                record = session.get(IdempotencyRecord, identity, with_for_update=True)
                if record is None:
                    continue
                if record.request_fingerprint != request_fingerprint:
                    raise IdempotencyConflict from None
                if record.status_code == IN_PROGRESS_STATUS:
                    provisional_user_id = record.response_body.get("user_id")
                    if route == "auth_signup" and isinstance(provisional_user_id, str):
                        try:
                            provisional_user_id = str(UUID(provisional_user_id))
                        except ValueError:
                            provisional_user_id = None
                    if route == "auth_signup" and provisional_user_id is not None:
                        # The signup transaction already committed the account
                        # if this marker is visible. Convert the interrupted
                        # claim into a durable, replayable delivery outcome;
                        # never run the provider again.
                        record.status_code = 503
                        record.response_body = {
                            "error": {
                                "code": "delivery_unknown",
                                "user_id": provisional_user_id,
                            }
                        }
                        return record.status_code, record.response_body
                    created_at = record.created_at
                    if created_at.tzinfo is None:
                        created_at = created_at.replace(tzinfo=UTC)
                    if created_at < datetime.now(UTC) - CLAIM_TIMEOUT:
                        session.execute(
                            delete(IdempotencyRecord).where(
                                IdempotencyRecord.route == route,
                                IdempotencyRecord.scope == scope,
                                IdempotencyRecord.idempotency_key == key,
                            )
                        )
                        continue
                    raise IdempotencyInProgress from None
                return record.status_code, record.response_body
    raise RuntimeError("idempotency claim disappeared during creation")


def store(
    sessions: sessionmaker[Session],
    *,
    route: str,
    scope: str,
    key: str,
    request_fingerprint: str,
    status_code: int,
    body: dict[str, Any],
    overwrite: bool = False,
) -> None:
    """Complete a key, optionally replacing a prior durable delivery outcome."""
    with sessions.begin() as session:
        record = session.get(IdempotencyRecord, (route, scope, key), with_for_update=True)
        if record is None:
            session.add(
                IdempotencyRecord(
                    route=route,
                    scope=scope,
                    idempotency_key=key,
                    request_fingerprint=request_fingerprint,
                    status_code=status_code,
                    response_body=body,
                )
            )
            return
        if record.request_fingerprint != request_fingerprint:
            raise IdempotencyConflict
        if record.status_code == IN_PROGRESS_STATUS or overwrite:
            record.status_code = status_code
            record.response_body = body


def abandon(sessions: sessionmaker[Session], *, route: str, scope: str, key: str) -> None:
    """Release a claim when the guarded mutation fails before completion."""
    with sessions.begin() as session:
        session.execute(
            delete(IdempotencyRecord).where(
                IdempotencyRecord.route == route,
                IdempotencyRecord.scope == scope,
                IdempotencyRecord.idempotency_key == key,
                IdempotencyRecord.status_code == IN_PROGRESS_STATUS,
            )
        )
