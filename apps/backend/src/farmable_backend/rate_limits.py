"""Durable, concurrency-safe abuse limits (#9).

Every limit is a sliding-window counter persisted in ``rate_limit_counters``,
so it survives process restarts and is safe under concurrent PostgreSQL
requests: the subject row is locked (``with_for_update``) for the rest of
the caller's transaction, so two concurrent hits against the same
scope+subject serialize instead of both reading a stale count.

Callers must run ``check()`` inside an already-open ``session.begin()``
transaction (mirroring the existing ``VoiceSessionRate``/``PhotoRate``
pattern in ``voice_api.py``/``records_service.py``).
"""

from __future__ import annotations

import hashlib
import math
from datetime import UTC, datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from farmable_backend.models import RateLimitCounter


class RateLimited(Exception):
    def __init__(self, code: str, retry_after: int):
        self.code = code
        self.retry_after = retry_after
        super().__init__(code)


def hash_subject(value: str) -> str:
    """Never persist a raw IP/phone; only its hash is stored as the row key."""
    return hashlib.sha256(value.encode()).hexdigest()


def _now_ts() -> float:
    return datetime.now(UTC).timestamp()


def check(
    session: Session,
    *,
    scope: str,
    subject: str,
    window_seconds: int,
    limit: int,
    code: str,
) -> None:
    """Record one hit for ``scope``+``subject``; raise RateLimited over the cap.

    Recording happens up front (not only on success) so a burst of requests
    that are each individually rejected still counts toward the window —
    otherwise a caller could retry indefinitely without ever being charged.
    """
    subject_hash = hash_subject(subject)
    now = _now_ts()
    counter = session.get(RateLimitCounter, (scope, subject_hash), with_for_update=True)
    if counter is None:
        try:
            with session.begin_nested():
                counter = RateLimitCounter(scope=scope, subject_hash=subject_hash, hits=[])
                session.add(counter)
                session.flush()
        except IntegrityError:
            # Lost the race to create the row; the winner's row is now visible.
            counter = session.get(RateLimitCounter, (scope, subject_hash), with_for_update=True)
    hits = [hit for hit in counter.hits if hit > now - window_seconds]
    if len(hits) >= limit:
        retry_after = max(1, math.ceil(min(hits) + window_seconds - now))
        counter.hits = hits
        raise RateLimited(code, retry_after)
    counter.hits = [*hits, now]
