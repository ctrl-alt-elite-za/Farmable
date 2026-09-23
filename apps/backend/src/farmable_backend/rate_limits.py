"""Durable, concurrency-safe abuse limits (#9).

Every limit is a sliding-window counter persisted in ``rate_limit_counters``,
so it survives process restarts and is safe under concurrent PostgreSQL
requests: the subject row is locked (``with_for_update``) only for the
duration of this short, dedicated transaction — never for the rest of the
caller's own transaction. Locking for the caller's whole transaction (an
earlier version of this module did) would serialize unrelated concurrent
requests from the same subject behind each other's full work, including
slow provider calls; this mirrors the existing ``VoiceSessionRate``/
``PhotoRate`` pattern in ``voice_api.py``/``records_service.py``, where the
rate check is its own short transaction, committed before the caller's
actual (possibly slow) work begins.
"""

from __future__ import annotations

import hashlib
import math
from datetime import UTC, datetime

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

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
    sessions: sessionmaker[Session],
    *,
    scope: str,
    subject: str,
    window_seconds: int,
    limit: int,
    code: str,
) -> None:
    """Record one hit for ``scope``+``subject``; raise RateLimited over the cap.

    Runs and commits its own short transaction — the row lock is released
    before this returns, regardless of how long the caller's subsequent work
    takes. Recording happens up front (not only on success) so a burst of
    requests that are each individually rejected still counts toward the
    window — otherwise a caller could retry indefinitely without ever being
    charged.
    """
    subject_hash = hash_subject(subject)
    now = _now_ts()
    with sessions.begin() as session:
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
            rejected = RateLimited(code, retry_after)
        else:
            counter.hits = [*hits, now]
            rejected = None
    if rejected is not None:
        raise rejected
