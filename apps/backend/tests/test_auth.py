import threading
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest
from farmable_backend.auth import (
    DEFAULT_FARM_NAME,
    DUMMY_PASSWORD_HASH,
    MAX_OTP_ATTEMPTS,
    AuthError,
    AuthService,
    Channel,
    DeterministicFakeOtpProvider,
    InMemoryAuthService,
    SessionTokens,
    _hash_token,
)
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.main import create_app
from farmable_backend.models import (
    AuthIdentity,
    AuthSession,
    Base,
    Farm,
    RateLimitCounter,
    User,
    VerificationChallenge,
)
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, delete, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import NullPool

PASSWORD = "correct horse battery staple"  # noqa: S105 - synthetic test credential


def client(settings):
    app = create_app(
        settings,
        readiness=lambda: {},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    app.state.auth = InMemoryAuthService()
    # TestClient(app) without a `with` block never runs the lifespan, so
    # app.state.services (normally set there) needs to be seeded by hand too.
    app.state.services = ServiceRegistry(
        ServiceSettings(environment="ci", integrations_mode="fake")
    )
    return TestClient(app), app.state.auth


def verified_account(settings):
    test_client, auth = client(settings)
    signup = test_client.post(
        "/auth/signup",
        json={
            "first_name": "Sipho",
            "surname": "Dlamini",
            "phone": "+27123456789",
            "email": "sipho@example.com",
            "password": PASSWORD,
            "turnstile_token": "fixture-token",
        },
    )
    assert signup.status_code == 200
    user_id = signup.json()["user_id"]
    assert auth.deliveries == [(Channel.PHONE, auth.deliveries[0][1])]
    assert (
        test_client.post("/auth/verify/phone", json={"user_id": user_id, "code": "111111"}).json()[
            "next_step"
        ]
        == "email"
    )
    complete = test_client.post("/auth/verify/email", json={"user_id": user_id, "code": "222222"})
    assert complete.status_code == 200
    return test_client, auth, complete.json()


def test_signup_verifies_phone_then_email_with_fake_provider(settings):
    test_client, auth, session = verified_account(settings)
    assert session["user"]["phone_verified"] is True
    assert session["user"]["email_verified"] is True
    assert [channel for channel, _ in auth.deliveries] == [Channel.PHONE, Channel.EMAIL]
    assert "111111" not in repr(auth.deliveries)
    test_client.close()


def test_email_and_phone_password_login_do_not_send_an_otp(settings):
    test_client, auth, _ = verified_account(settings)
    before = list(auth.deliveries)
    for identifier in ("sipho@example.com", "+27123456789"):
        response = test_client.post(
            "/auth/login",
            json={
                "identifier": identifier,
                "password": PASSWORD,
                "turnstile_token": "fixture-token",
            },
        )
        assert response.status_code == 200
        assert response.json()["refresh_token"]
    assert auth.deliveries == before
    test_client.close()


def test_unverified_account_cannot_log_in_and_errors_are_generic(settings):
    test_client, _ = client(settings)
    test_client.post(
        "/auth/signup",
        json={
            "first_name": "Nandi",
            "surname": "Mokoena",
            "phone": "+27820000000",
            "email": "nandi@example.com",
            "password": PASSWORD,
            "turnstile_token": "fixture-token",
        },
    )
    unverified = test_client.post(
        "/auth/login",
        json={
            "identifier": "nandi@example.com",
            "password": PASSWORD,
            "turnstile_token": "fixture-token",
        },
    )
    missing = test_client.post(
        "/auth/login",
        json={
            "identifier": "missing@example.com",
            "password": PASSWORD,
            "turnstile_token": "fixture-token",
        },
    )
    assert unverified.status_code == 401
    assert missing.status_code == 401
    assert unverified.json() == missing.json()
    assert missing.json() == {
        "error": {"code": "invalid_credentials", "message": "Unable to log in with those details"}
    }
    test_client.close()


def test_missing_account_still_performs_password_verification(monkeypatch):
    _sessions, service = _database_auth()
    verified_hashes: list[str] = []

    def reject(password_hash: str, password: str) -> bool:
        verified_hashes.append(password_hash)
        return False

    monkeypatch.setattr(service, "_verify_password", reject)
    with pytest.raises(AuthError, match="invalid_credentials"):
        service.login("missing@example.com", PASSWORD)

    assert verified_hashes == [DUMMY_PASSWORD_HASH]


def test_login_lockout_is_checked_before_a_correct_password():
    _sessions, service = _database_auth()
    user = service.signup("Sipho", "Dlamini", "+27123456789", "sipho@example.com", PASSWORD)
    service.verify(user.id, Channel.PHONE, "111111")
    service.verify(user.id, Channel.EMAIL, "222222")
    for _ in range(5):
        with pytest.raises(AuthError, match="invalid_credentials"):
            service.login("sipho@example.com", "wrong password")
    with pytest.raises(AuthError, match="login_rate_limited"):
        service.login("sipho@example.com", PASSWORD)


def test_parallel_login_failures_fence_a_paused_valid_request(tmp_path, monkeypatch):
    """Five failures completed while Argon2 is paused cannot mint a token."""
    engine = create_engine(
        f"sqlite+pysqlite:///{tmp_path / 'login-race.db'}",
        connect_args={"check_same_thread": False, "timeout": 30},
        poolclass=NullPool,
    )
    Base.metadata.create_all(
        engine,
        tables=[
            User.__table__,
            Farm.__table__,
            AuthIdentity.__table__,
            VerificationChallenge.__table__,
            AuthSession.__table__,
            RateLimitCounter.__table__,
        ],
    )
    sessions = sessionmaker(engine, expire_on_commit=False)
    service = AuthService(sessions, DeterministicFakeOtpProvider())
    user = service.signup("Sipho", "Dlamini", "+27123456789", "sipho@example.com", PASSWORD)
    service.verify(user.id, Channel.PHONE, "111111")
    service.verify(user.id, Channel.EMAIL, "222222")
    # Email verification creates an authenticated session. Remove that setup
    # session so this race test only observes a token minted by login.
    with sessions.begin() as session:
        session.execute(delete(AuthSession))
    original_verify = service._verify_password
    valid_started = threading.Event()
    release_valid = threading.Event()

    def paused_verify(password_hash, password):
        if password == PASSWORD:
            valid_started.set()
            assert release_valid.wait(30)
        return original_verify(password_hash, password)

    monkeypatch.setattr(service, "_verify_password", paused_verify)

    def login(password):
        try:
            service.login("sipho@example.com", password, ip="race-ip")
        except AuthError as exc:
            return exc.code
        return "success"

    with ThreadPoolExecutor(max_workers=7) as executor:
        valid = executor.submit(login, PASSWORD)
        assert valid_started.wait(30)
        failures = [executor.submit(login, "wrong password") for _ in range(5)]
        assert [future.result() for future in failures] == ["invalid_credentials"] * 5
        # A fresh wrong-password request must eventually be rejected by the
        # lockout before entering password verification; the already-paused
        # valid request below verifies the concurrent success fence. SQLite
        # may commit the parallel failure transactions in a different order,
        # so allow the final counter update to become visible first.
        fresh_results = [login("wrong password") for _ in range(3)]
        assert "login_rate_limited" in fresh_results
        release_valid.set()
        assert valid.result() == "login_rate_limited"

    with sessions() as session:
        assert session.scalar(select(AuthSession)) is None
    engine.dispose()


def test_refresh_rotates_a_session(settings):
    test_client, _, session = verified_account(settings)
    refreshed = test_client.post("/auth/refresh", json={"refresh_token": session["refresh_token"]})
    assert refreshed.status_code == 200
    assert refreshed.json()["refresh_token"] != session["refresh_token"]
    assert (
        test_client.post(
            "/auth/refresh", json={"refresh_token": session["refresh_token"]}
        ).status_code
        == 401
    )
    test_client.close()


def _database_auth():
    engine = create_engine("sqlite://")
    Base.metadata.create_all(
        engine,
        tables=[
            User.__table__,
            Farm.__table__,
            AuthIdentity.__table__,
            VerificationChallenge.__table__,
            AuthSession.__table__,
            RateLimitCounter.__table__,
        ],
    )
    sessions = sessionmaker(engine, expire_on_commit=False)
    return sessions, AuthService(sessions, DeterministicFakeOtpProvider())


def test_database_service_persists_attempt_limit_and_only_hashes_secrets():
    sessions, service = _database_auth()
    user = service.signup("Sipho", "Dlamini", "+27123456789", "sipho@example.com", PASSWORD)

    for _ in range(MAX_OTP_ATTEMPTS):
        with pytest.raises(AuthError, match="invalid_verification"):
            service.verify(user.id, Channel.PHONE, "000000")
    with pytest.raises(AuthError, match="invalid_verification"):
        service.verify(user.id, Channel.PHONE, "111111")

    with sessions() as session:
        stored_user = session.get(AuthIdentity, user.id)
        challenge = session.scalar(select(VerificationChallenge))
        assert stored_user is not None and stored_user.password_hash != PASSWORD
        assert challenge is not None and challenge.code_hash != "111111"
        assert challenge.attempts == MAX_OTP_ATTEMPTS


def test_database_service_stores_only_token_hashes_and_rotates_refresh():
    sessions, service = _database_auth()
    user = service.signup("Sipho", "Dlamini", "+27123456789", "sipho@example.com", PASSWORD)
    service.verify(user.id, Channel.PHONE, "111111")
    tokens = service.verify(user.id, Channel.EMAIL, "222222")
    assert isinstance(tokens, SessionTokens)

    with sessions() as session:
        stored = session.scalar(select(AuthSession))
        assert stored is not None
        assert stored.access_token_hash == _hash_token(tokens.access_token)
        assert stored.refresh_token_hash == _hash_token(tokens.refresh_token)
        assert tokens.access_token not in repr(stored)
        assert tokens.refresh_token not in repr(stored)

    rotated = service.refresh(tokens.refresh_token)
    assert rotated.refresh_token != tokens.refresh_token
    with pytest.raises(AuthError, match="invalid_session"):
        service.refresh(tokens.refresh_token)


def test_database_service_rate_limits_resends_and_invalidates_old_code():
    sessions, service = _database_auth()
    user = service.signup("Sipho", "Dlamini", "+27123456789", "sipho@example.com", PASSWORD)
    service.resend(user.id, Channel.PHONE)
    service.resend(user.id, Channel.PHONE)
    with pytest.raises(AuthError, match="sms_phone_rate_limited"):
        service.resend(user.id, Channel.PHONE)

    with sessions() as session:
        challenges = session.scalars(
            select(VerificationChallenge).order_by(VerificationChallenge.created_at)
        ).all()
        assert len(challenges) == 3
        assert all(item.consumed_at is not None for item in challenges[:-1])
        assert challenges[-1].consumed_at is None


@pytest.mark.parametrize(
    ("sqlstate", "constraint", "conflict"),
    [
        ("23505", "uq_auth_identities_email", True),
        ("23505", "uq_auth_identities_phone", True),
        ("23505", "users_pkey", False),
        ("23514", "ck_auth_identities_first_name_nonblank", False),
        ("23503", "uq_auth_identities_email", False),
    ],
)
def test_signup_only_translates_credential_unique_violations(sqlstate, constraint, conflict):
    class DatabaseFailure(Exception):
        pass

    original = DatabaseFailure()
    original.sqlstate = sqlstate
    original.diag = SimpleNamespace(constraint_name=constraint)
    failure = IntegrityError("generated statement", {}, original)
    sessions = MagicMock()
    transaction = sessions.begin.return_value
    session = transaction.__enter__.return_value
    session.scalar.return_value = None
    # An existing counter row for every rate-limit scope checked (signup_ip,
    # sms_ip, sms_daily), so none of those take the row-creation branch and
    # add their own flush() calls — only the real owner/identity inserts do.
    session.get.return_value = RateLimitCounter(scope="x", subject_hash="y", hits=[])
    # A real SAVEPOINT context manager propagates an exception raised inside
    # it; MagicMock's auto-mocked __exit__ would otherwise swallow it (any
    # truthy return value suppresses the exception).
    session.begin_nested.return_value.__exit__.return_value = False
    # The owner-row insert flushes first; only the credential (AuthIdentity)
    # insert's flush should hit the simulated unique-constraint failure.
    calls = {"n": 0}

    def flush_side_effect():
        calls["n"] += 1
        if calls["n"] == 2:
            raise failure

    session.flush.side_effect = flush_side_effect
    provider = MagicMock()
    service = AuthService(sessions, provider)
    if conflict:
        # #9 enumeration resistance: a credential collision (even one only
        # discovered via a race at flush time) returns the same public shape
        # as a new sign-up, never a distinguishable error.
        user = service.signup("Test", "User", "+27820000000", "test@example.com", PASSWORD)
        assert user.email == "test@example.com"
        # The conflict is caught and handled inside a nested SAVEPOINT, so
        # the outer transaction commits normally (the rate-limit hit
        # recorded earlier in it is never rolled back by the collision).
        assert transaction.__exit__.call_args.args[0] is None
    else:
        with pytest.raises(IntegrityError) as caught:
            service.signup("Test", "User", "+27820000000", "test@example.com", PASSWORD)
        assert caught.value is failure
        # An unrecognised conflict re-raises past the savepoint and exits
        # the outer transaction too.
        assert transaction.__exit__.call_args.args[0] is IntegrityError
    provider.deliver.assert_not_called()


def test_signup_creates_the_owner_empty_farm():
    sessions, service = _database_auth()
    user = service.signup("Sipho", "Dlamini", "+27123456789", "sipho@example.com", PASSWORD)

    with sessions() as session:
        farms = session.scalars(select(Farm).where(Farm.owner_id == user.id)).all()
    assert [farm.name for farm in farms] == [DEFAULT_FARM_NAME]
    assert [farm.deleted_at for farm in farms] == [None]
