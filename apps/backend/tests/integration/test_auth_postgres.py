"""PostgreSQL concurrency coverage for authentication token rotation."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Lock
from types import SimpleNamespace
from uuid import uuid4

import pytest
from farmable_backend import auth as auth_module
from farmable_backend import rate_limits as limits
from farmable_backend.auth import (
    PASSWORD_HASHER,
    AuthError,
    AuthService,
    AuthUser,
    Channel,
    DeterministicFakeOtpProvider,
    SessionTokens,
)
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.models import (
    AuthIdentity,
    AuthSession,
    RateLimitCounter,
    User,
    VerificationChallenge,
)
from sqlalchemy import delete, event, func, select
from sqlalchemy.orm import Session, sessionmaker

pytestmark = pytest.mark.integration


@pytest.fixture
def engine():
    value = make_engine(Settings())
    yield value
    value.dispose()


def test_auth_login_leases_bound_parallel_admission_and_recover(engine, monkeypatch):
    sessions = sessionmaker(engine, expire_on_commit=False)
    suffix = uuid4().hex
    args = {"account": suffix + "@example.com", "ip": suffix}
    subjects = [limits.hash_subject(value) for value in args.values()]
    monkeypatch.setattr(limits, "LOGIN_IN_FLIGHT_LIMIT", 2)
    monkeypatch.setattr(limits, "_now_ts", lambda: 1000.0)
    barrier = Barrier(8, timeout=10)

    def admit(_):
        barrier.wait()
        try:
            return limits.admit_login(sessions, **args)
        except limits.RateLimited:
            return None

    try:
        with ThreadPoolExecutor(max_workers=8) as pool:
            tickets = [ticket for ticket in pool.map(admit, range(8)) if ticket]
        assert len(tickets) == 2
        monkeypatch.setattr(limits, "_now_ts", lambda: 1060.0)
        replacement = limits.admit_login(sessions, **args)
        with sessions.begin() as session:
            assert not limits.finish_login(session, **args, reservation=tickets[0], success=True)
        with sessions.begin() as session:
            assert limits.finish_login(session, **args, reservation=replacement, success=True)
    finally:
        with sessions.begin() as session:
            session.execute(
                delete(RateLimitCounter).where(RateLimitCounter.subject_hash.in_(subjects))
            )


def test_auth_parallel_failures_preserve_count_and_fence_success(engine):
    sessions = sessionmaker(engine, expire_on_commit=False)
    suffix = uuid4().hex
    args = {"account": suffix + "@example.com", "ip": suffix}
    subjects = [limits.hash_subject(value) for value in args.values()]
    late = limits.admit_login(sessions, **args)
    tickets = [limits.admit_login(sessions, **args) for _ in range(5)]
    barrier = Barrier(5, timeout=10)

    def fail(ticket):
        barrier.wait()
        with sessions.begin() as session:
            return limits.finish_login(session, **args, reservation=ticket, success=False)

    try:
        with ThreadPoolExecutor(max_workers=5) as pool:
            assert list(pool.map(fail, tickets)) == [True] * 5
        with sessions.begin() as session:
            assert not limits.finish_login(session, **args, reservation=late, success=True)
        with sessions() as session:
            rows = session.scalars(
                select(RateLimitCounter).where(RateLimitCounter.subject_hash.in_(subjects))
            ).all()
            assert len(rows) == 2
            assert all(
                len(row.hits) == 5 and row.in_flight == 0 and not row.login_leases for row in rows
            )
    finally:
        with sessions.begin() as session:
            session.execute(
                delete(RateLimitCounter).where(RateLimitCounter.subject_hash.in_(subjects))
            )


def test_refresh_token_can_only_be_rotated_once_concurrently(engine):
    suffix = uuid4().hex
    sessions = sessionmaker(engine, expire_on_commit=False)
    service = AuthService(sessions, DeterministicFakeOtpProvider())
    user = service.signup(
        "Sipho",
        "Dlamini",
        f"+27{int(suffix[:10], 16) % 10_000_000_000:010d}",
        f"auth-{suffix}@example.com",
        "correct horse battery staple",
        ip=f"198.51.100.{(int(suffix[:2], 16) % 250) + 1}",
    )
    service.verify(user.id, Channel.PHONE, "111111")
    tokens = service.verify(user.id, Channel.EMAIL, "222222")
    assert isinstance(tokens, SessionTokens)
    barrier = Barrier(2)

    def rotate() -> SessionTokens | AuthError:
        barrier.wait(timeout=10)
        try:
            return service.refresh(tokens.refresh_token)
        except AuthError as exc:
            return exc

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(lambda _index: rotate(), range(2)))

        assert sum(isinstance(result, SessionTokens) for result in results) == 1
        failures = [result for result in results if isinstance(result, AuthError)]
        assert len(failures) == 1
        assert failures[0].code == "invalid_session"
    finally:
        with Session(engine) as session:
            stored = session.get(User, user.id)
            if stored is not None:
                session.delete(stored)
                session.commit()


@pytest.mark.parametrize("duplicate", ["email", "phone"])
def test_auth_concurrent_signup_returns_conflict_without_orphans(engine, monkeypatch, duplicate):
    suffix = uuid4().hex
    sessions = sessionmaker(engine, expire_on_commit=False)
    barrier = Barrier(2)
    lock = Lock()
    created_ids = []
    deliveries = []

    class RecordingProvider(DeterministicFakeOtpProvider):
        def deliver(self, channel, destination, code):
            with lock:
                deliveries.append((channel, destination))
            super().deliver(channel, destination, code)

    # Both transactions must finish the optimistic existence check before either
    # attempts INSERT. Hashing follows that check and precedes all writes.
    password = "concurrent synthetic signup password"  # noqa: S105
    original_hash = PASSWORD_HASHER.hash

    def synchronized_hash(value):
        if value == password:
            barrier.wait(timeout=10)
        return original_hash(value)

    monkeypatch.setattr(
        auth_module,
        "PASSWORD_HASHER",
        SimpleNamespace(hash=synchronized_hash, verify=PASSWORD_HASHER.verify),
    )

    def record_users(session, flush_context):
        with lock:
            created_ids.extend(
                item.id for item in session.identity_map.values() if isinstance(item, User)
            )

    event.listen(sessions, "after_flush_postexec", record_users)
    service = AuthService(sessions, RecordingProvider())
    phone = int(suffix[:10], 16) % 1_000_000_000

    def signup(index):
        try:
            return service.signup(
                "Test",
                "User",
                f"+278{phone + (index if duplicate == 'email' else 0):09d}",
                f"auth-race-{suffix}-{index if duplicate == 'phone' else 0}@example.com",
                password,
                ip=f"198.51.100.{(int(suffix[:2], 16) % 250) + 1}",
            )
        except AuthError as exc:
            return exc

    try:
        with ThreadPoolExecutor(max_workers=2) as executor:
            results = list(executor.map(signup, range(2)))
        # #9 enumeration resistance: the losing signup no longer raises
        # account_exists — it gets the same public shape as a genuine
        # sign-up, just with a fabricated id and no account/OTP of its own.
        assert all(isinstance(result, AuthUser) for result in results)
        assert len(deliveries) == 1
        assert len(set(created_ids)) == 2  # Even the losing user INSERT occurred.
        with Session(engine) as session:
            for model in (User, AuthIdentity):
                assert (
                    session.scalar(
                        select(func.count()).select_from(model).where(model.id.in_(created_ids))
                    )
                    == 1
                )
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(VerificationChallenge)
                    .where(VerificationChallenge.user_id.in_(created_ids))
                )
                == 1
            )
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(AuthSession)
                    .where(AuthSession.user_id.in_(created_ids))
                )
                == 0
            )
    finally:
        with Session(engine) as session:
            for user in session.scalars(select(User).where(User.id.in_(created_ids))):
                session.delete(user)
            session.commit()
