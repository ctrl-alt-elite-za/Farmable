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
from typing import Any

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.models import IdempotencyRecord


class IdempotencyConflict(Exception):
    """Same key, different request body."""


def fingerprint(payload: dict[str, Any]) -> str:
    canonical = json.dumps(payload, sort_keys=True, separators=(",", ":"), default=str)
    return hashlib.sha256(canonical.encode()).hexdigest()


def replay(
    sessions: sessionmaker[Session], *, route: str, key: str, request_fingerprint: str
) -> tuple[int, dict[str, Any]] | None:
    """Return the stored (status_code, body) for a prior identical request, if any."""
    with sessions.begin() as session:
        record = session.get(IdempotencyRecord, (route, key))
        if record is None:
            return None
        if record.request_fingerprint != request_fingerprint:
            raise IdempotencyConflict
        return record.status_code, record.response_body


def store(
    sessions: sessionmaker[Session],
    *,
    route: str,
    key: str,
    request_fingerprint: str,
    status_code: int,
    body: dict[str, Any],
) -> None:
    """Persist a response for future replays. Safe if another request already did."""
    try:
        with sessions.begin() as session:
            session.add(
                IdempotencyRecord(
                    route=route,
                    idempotency_key=key,
                    request_fingerprint=request_fingerprint,
                    status_code=status_code,
                    response_body=body,
                )
            )
    except IntegrityError:
        pass  # A concurrent replay of the same key already stored this response.
