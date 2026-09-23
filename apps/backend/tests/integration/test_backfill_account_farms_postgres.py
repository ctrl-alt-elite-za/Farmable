"""PostgreSQL coverage for backfill_account_farms's concurrency guard."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest
from farmable_backend.backfill_account_farms import backfill_account_farms
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.models import AuthIdentity, Farm, User
from sqlalchemy import select
from sqlalchemy.orm import Session

pytestmark = pytest.mark.integration

PASSWORD_HASH = "$argon2id$v=19$m=65536,t=3,p=4$placeholder"  # noqa: S105 - synthetic


@pytest.fixture
def engine():
    value = make_engine(Settings())
    yield value
    value.dispose()


def test_concurrent_runs_create_exactly_one_farm_per_identity(engine):
    """The race the advisory lock in backfill_account_farms exists to close.

    Without `pg_advisory_xact_lock`, two overlapping invocations both read
    the same ownerless identity under READ COMMITTED (there is no unique
    constraint on farms(owner_id) to fall back on) and both insert -- a
    second, permanently orphaned farm that no endpoint can ever reach, since
    AccountService._farm always serves the oldest live farm. With the lock,
    the second invocation's transaction blocks until the first commits, then
    reads the now-owned identity and correctly inserts nothing.

    A barrier placed before each thread opens its Session is NOT sufficient:
    connection-pool checkout is asymmetric between threads (as with the
    language-write race test), so one thread can reach, execute and commit
    past the advisory lock before the second thread's transaction ever
    starts -- no contention occurs and the test passes whether or not the
    lock exists.

    Synchronizing on the ownerless-identity SELECT statement itself (as the
    language-write test does on its lock statement) does not work here
    either: with the fix present, that SELECT comes *after* the advisory
    lock acquisition, so the second thread cannot reach it until the first
    commits and releases the lock -- but the first thread is waiting at the
    same barrier for the second to arrive there too. That is a deadlock
    between "wait for the barrier" and "wait for the lock", not a race.

    An engine-level `checkout` hook does not work either, and fails louder:
    QueuePool dispatches that event while still holding its own internal
    bookkeeping lock, so the first thread's barrier.wait() inside the hook
    blocks the pool from ever completing the second thread's checkout --
    the two threads deadlock against the pool itself, not each other.

    Instead, both sessions acquire and warm their connection (a trivial
    `SELECT 1`, no different from what `backfill_account_farms` will need
    anyway) *before* the timed section starts, outside any barrier. With
    connection-checkout out of the way, a plain barrier immediately before
    the call to `backfill_account_farms` is enough: the only asymmetry left
    is ordinary Python/OS thread scheduling, not an I/O-bound setup step,
    and what happens next is decided by the advisory lock (or its absence).
    """
    suffix = uuid4().hex
    owner_id = None
    with Session(engine) as session:
        owner = User()
        session.add(owner)
        session.flush()
        session.add(
            AuthIdentity(
                id=owner.id,
                first_name="Sipho",
                surname="Dlamini",
                phone=f"+27831{suffix[:6]}",
                email=f"backfill-{suffix}@example.com",
                password_hash=PASSWORD_HASH,
                phone_verified=True,
                email_verified=True,
            )
        )
        session.commit()
        owner_id = owner.id

    runs = 2
    call_barrier = Barrier(runs, timeout=10)
    sessions = [Session(engine) for _ in range(runs)]
    for warm in sessions:
        warm.execute(select(1))  # force connection checkout now, not during the race

    def run(session):
        call_barrier.wait()
        created = backfill_account_farms(session)
        session.commit()
        return created

    try:
        with ThreadPoolExecutor(max_workers=runs) as executor:
            created_counts = list(executor.map(run, sessions))
        # Exactly one of the two overlapping runs should have found and
        # created the farm; the other, serialized behind the advisory lock,
        # must see it already exists.
        assert sorted(created_counts) == [0, 1]
        with Session(engine) as session:
            farms = session.scalars(select(Farm).where(Farm.owner_id == owner_id)).all()
            assert len(farms) == 1
    finally:
        for warm in sessions:
            warm.close()
        with Session(engine) as session:
            identity = session.get(AuthIdentity, owner_id)
            if identity is not None:
                session.delete(identity)
            farms = session.scalars(select(Farm).where(Farm.owner_id == owner_id)).all()
            for farm in farms:
                session.delete(farm)
            user = session.get(User, owner_id)
            if user is not None:
                session.delete(user)
            session.commit()
