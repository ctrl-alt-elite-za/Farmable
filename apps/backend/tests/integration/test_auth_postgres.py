"""PostgreSQL concurrency coverage for authentication token rotation."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier, Lock
from types import SimpleNamespace
from uuid import uuid4

import pytest
from farmable_backend import auth as auth_module
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
from farmable_backend.models import AuthIdentity, AuthSession, User, VerificationChallenge
from sqlalchemy import event, func, select
from sqlalchemy.orm import Session, sessionmaker

pytestmark = pytest.mark.integration


@pytest.fixture
def engine():
    value = make_engine(Settings())
    yield value
    value.dispose()


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
