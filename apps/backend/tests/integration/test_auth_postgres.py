"""PostgreSQL concurrency coverage for authentication token rotation."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest
from farmable_backend.auth import (
    AuthError,
    AuthService,
    Channel,
    DeterministicFakeOtpProvider,
    SessionTokens,
)
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.models import User
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
