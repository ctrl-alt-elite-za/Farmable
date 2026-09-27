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
from uuid import uuid4

from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.models import RateLimitCounter

LOGIN_IN_FLIGHT_LIMIT = 32
LOGIN_LEASE_SECONDS = 60


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
        if counter is None:
            raise RuntimeError("rate-limit counter disappeared during creation")
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


def retry_after_if_limited(
    sessions: sessionmaker[Session],
    *,
    scope: str,
    subject: str,
    window_seconds: int,
    limit: int,
) -> int | None:
    """Return the lockout delay without consuming another admission slot."""
    now = _now_ts()
    with sessions.begin() as session:
        counter = session.get(
            RateLimitCounter, (scope, hash_subject(subject)), with_for_update=True
        )
        if counter is None:
            return None
        hits = [hit for hit in counter.hits if hit > now - window_seconds]
        counter.hits = hits
        if len(hits) < limit:
            return None
        return max(1, math.ceil(min(hits) + window_seconds - now))


def _locked_counter(session: Session, *, scope: str, subject: str) -> RateLimitCounter:
    """Get/create a counter while retaining a row lock in ``session``."""
    subject_hash = hash_subject(subject)
    counter = session.get(RateLimitCounter, (scope, subject_hash), with_for_update=True)
    if counter is None:
        try:
            with session.begin_nested():
                counter = RateLimitCounter(scope=scope, subject_hash=subject_hash, hits=[])
                session.add(counter)
                session.flush()
        except IntegrityError:
            counter = session.get(RateLimitCounter, (scope, subject_hash), with_for_update=True)
    if counter is None:
        raise RuntimeError("rate-limit counter disappeared during creation")
    return counter


def _active_login_leases(counter: RateLimitCounter, now: float) -> dict[str, float]:
    return {key: expiry for key, expiry in counter.login_leases.items() if expiry > now}


def admit_login(sessions: sessionmaker[Session], *, account: str, ip: str) -> str:
    """Reserve one bounded login verification across both abuse buckets.

    The reservations are durable and locked in one transaction, so separate
    API replicas cannot all start unbounded Argon2 work from the same stale
    counter value. Individual expiring leases recover capacity after a process
    crash and prevent a late completion from releasing another request's slot.
    """
    reservation = uuid4().hex
    limits = (
        ("login_fail_account", account, 5),
        ("login_fail_ip", ip, 20),
    )
    with sessions.begin() as session:
        counters = [
            (scope, _locked_counter(session, scope=scope, subject=subject), limit)
            for scope, subject, limit in limits
        ]
        now = _now_ts()
        for _scope, counter, limit in counters:
            counter.hits = [hit for hit in counter.hits if hit > now - 900]
            leases = _active_login_leases(counter, now)
            if len(counter.hits) >= limit or len(leases) >= LOGIN_IN_FLIGHT_LIMIT:
                deadline = (
                    min(counter.hits) + 900 if len(counter.hits) >= limit else min(leases.values())
                )
                retry_after = max(1, math.ceil(deadline - now))
                raise RateLimited("login_rate_limited", retry_after)
            counter.login_leases = leases
        for _scope, counter, _limit in counters:
            counter.login_leases = {**counter.login_leases, reservation: now + LOGIN_LEASE_SECONDS}
            counter.in_flight = len(counter.login_leases)
    return reservation


def finish_login(
    session: Session,
    *,
    account: str,
    ip: str,
    success: bool,
    reservation: str,
) -> bool:
    """Consume a login reservation and return whether the request is fenced.

    The caller must use the same transaction for this function and session
    insertion. On a successful password check, ``False`` means the lockout
    became authoritative while Argon2 was running, so no session may be
    issued. On failure, the newly recorded hit is reflected by the return
    value.
    """
    limits = (
        ("login_fail_account", account, 5),
        ("login_fail_ip", ip, 20),
    )
    counters = [
        (counter, limit)
        for scope, subject, limit in limits
        for counter in [_locked_counter(session, scope=scope, subject=subject)]
    ]
    now = _now_ts()
    lease_valid = True
    for counter, _limit in counters:
        leases = _active_login_leases(counter, now)
        lease_valid = lease_valid and reservation in leases
        leases.pop(reservation, None)
        counter.login_leases = leases
        counter.in_flight = len(leases)
        counter.hits = [hit for hit in counter.hits if hit > now - 900]
    if not lease_valid:
        return False
    was_admitted = all(len(counter.hits) < limit for counter, limit in counters)
    if not success:
        for counter, _limit in counters:
            counter.hits = [*counter.hits, now]
        return was_admitted
    return all(len(counter.hits) < limit for counter, limit in counters)
