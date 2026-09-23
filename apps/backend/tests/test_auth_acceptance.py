"""Issue #9 named acceptance tests, run as repo-standard TestClient checks (#9).

The repo's e2e/api suite runs against one already-running production stack
started by `make e2e-api`, which has no per-test hook for toggling
integration faults (Turnstile down, etc.) without restarting the whole
stack. These tests exercise the same acceptance scenarios named in issue #9
against the FastAPI app directly with SQLite + the fake providers, which is
this repo's established pattern for auth behavior tests (see test_auth.py).
"""

from datetime import UTC, datetime
from uuid import uuid4

import pytest
from farmable_backend.auth import AuthService, DeterministicFakeOtpProvider
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.main import create_app
from farmable_backend.models import (
    AuthIdentity,
    AuthSession,
    Base,
    Farm,
    IdempotencyRecord,
    RateLimitCounter,
    User,
    VerificationChallenge,
)
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

PASSWORD = "correct horse battery staple"  # noqa: S105 - synthetic test credential


class CountingOtpProvider:
    """Wraps the deterministic fake OTP provider and counts real deliveries."""

    def __init__(self):
        self.inner = DeterministicFakeOtpProvider()
        self.deliveries = 0

    def create_code(self, channel):
        return self.inner.create_code(channel)

    def deliver(self, channel, destination, code):
        self.deliveries += 1
        self.inner.deliver(channel, destination, code)

    def notify_existing_account(self, channel, destination):
        self.inner.notify_existing_account(channel, destination)


def _engine():
    from sqlalchemy.pool import StaticPool

    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
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
            IdempotencyRecord.__table__,
        ],
    )
    return engine


def _app(settings, provider=None):
    engine = _engine()
    sessions = sessionmaker(engine, expire_on_commit=False)
    provider = provider or CountingOtpProvider()
    auth = AuthService(sessions, provider)
    app = create_app(
        settings,
        readiness=lambda: {},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    app.state.auth = auth
    app.state.services = ServiceRegistry(
        ServiceSettings(environment="ci", integrations_mode="fake")
    )
    return app, auth, provider, sessions


def _signup_body(**overrides):
    body = {
        "first_name": "Sipho",
        "surname": "Dlamini",
        "phone": "+27123456789",
        "email": "sipho@example.com",
        "password": PASSWORD,
        "turnstile_token": "fixture-token",
    }
    body.update(overrides)
    return body


def _signup_request(client, body=None, *, key=None):
    return client.post(
        "/auth/signup",
        json=body or _signup_body(),
        headers={"Idempotency-Key": key or f"test-signup-{uuid4().hex}"},
    )


def _resend_request(client, user_id, *, key=None):
    return client.post(
        "/auth/otp/resend",
        json={"user_id": user_id, "channel": "phone"},
        headers={"Idempotency-Key": key or f"test-resend-{uuid4().hex}"},
    )


def test_signup_verify_login(settings):
    app, _, provider, _ = _app(settings)
    with TestClient(app) as client:
        signup = _signup_request(client)
        assert signup.status_code == 200
        user_id = signup.json()["user_id"]
        client.post("/auth/verify/phone", json={"user_id": user_id, "code": "111111"})
        complete = client.post("/auth/verify/email", json={"user_id": user_id, "code": "222222"})
        assert complete.status_code == 200
        login = client.post(
            "/auth/login",
            json={
                "identifier": "sipho@example.com",
                "password": PASSWORD,
                "turnstile_token": "fixture-token",
            },
        )
        assert login.status_code == 200
        assert login.json()["refresh_token"]
    assert provider.deliveries == 2  # phone + email OTPs only, never during login


def test_sms_rate_limit_per_phone(settings):
    app, _, provider, _ = _app(settings)
    with TestClient(app) as client:
        signup = _signup_request(client)
        user_id = signup.json()["user_id"]
        # Sign-up already sent send #1. Two explicit resends bring it to 3.
        assert (
            client.post(
                "/auth/otp/resend",
                json={"user_id": user_id, "channel": "phone"},
                headers={"Idempotency-Key": "test-resend-key-0001"},
            ).status_code
            == 204
        )
        assert (
            client.post(
                "/auth/otp/resend",
                json={"user_id": user_id, "channel": "phone"},
                headers={"Idempotency-Key": "test-resend-key-0002"},
            ).status_code
            == 204
        )
        fourth = _resend_request(client, user_id, key="test-resend-key-0004")
        assert fourth.status_code == 429
        assert "Retry-After" in fourth.headers
    assert provider.deliveries == 3


def test_sms_daily_global_cap(settings):
    app, auth, provider, sessions = _app(settings)
    # Directly exhaust the daily counter (51 distinct phones would be slow and
    # is exactly what the durable counter is for) then confirm the 51st send
    # via the real signup path is rejected with no provider call.
    with sessions.begin() as session:
        now = datetime.now(UTC).timestamp()
        session.add(
            RateLimitCounter(scope="sms_daily", subject_hash=_hash("global"), hits=[now] * 50)
        )
    with TestClient(app) as client:
        response = _signup_request(client, _signup_body(phone="+27820000099"))
    assert response.status_code == 429
    assert response.json()["error"]["code"] == "daily_sms_cap"
    assert provider.deliveries == 0
    with sessions() as session:
        assert session.scalar(select(AuthIdentity)) is None  # no half-completed sign-up


def _hash(value: str) -> str:
    from farmable_backend.rate_limits import hash_subject

    return hash_subject(value)


def test_refresh_reuse_revokes_all(settings):
    app, _, _, sessions = _app(settings)
    with TestClient(app) as client:
        signup = _signup_request(client)
        user_id = signup.json()["user_id"]
        client.post("/auth/verify/phone", json={"user_id": user_id, "code": "111111"})
        session_a = client.post(
            "/auth/verify/email", json={"user_id": user_id, "code": "222222"}
        ).json()
        session_b = client.post(
            "/auth/login",
            json={
                "identifier": "sipho@example.com",
                "password": PASSWORD,
                "turnstile_token": "fixture-token",
            },
        ).json()
        rotated = client.post("/auth/refresh", json={"refresh_token": session_a["refresh_token"]})
        assert rotated.status_code == 200
        reused = client.post("/auth/refresh", json={"refresh_token": session_a["refresh_token"]})
        assert reused.status_code == 401
        # Every session for the user, including the unrelated session_b and
        # the just-rotated replacement, is now revoked.
        still_valid = client.post(
            "/auth/refresh", json={"refresh_token": rotated.json()["refresh_token"]}
        )
        assert still_valid.status_code == 401
        b_revoked = client.post("/auth/refresh", json={"refresh_token": session_b["refresh_token"]})
        assert b_revoked.status_code == 401
    with sessions() as session:
        user = session.scalar(select(AuthIdentity))
        live = session.scalars(
            select(AuthSession).where(
                AuthSession.user_id == user.id, AuthSession.revoked_at.is_(None)
            )
        ).all()
        assert live == []


def test_signup_existing_email_same_response(settings):
    app, _, provider, sessions = _app(settings)
    with TestClient(app) as client:
        first = _signup_request(client)
        assert first.status_code == 200
        deliveries_after_first = provider.deliveries
        second = _signup_request(
            client, _signup_body(phone="+27820000001", first_name="Someone Else")
        )
        assert second.status_code == first.status_code
        assert set(second.json()) == set(first.json())
        assert second.json()["next_step"] == first.json()["next_step"]
    assert provider.deliveries == deliveries_after_first  # no OTP sent for the collision
    with sessions() as session:
        assert len(session.scalars(select(AuthIdentity)).all()) == 1  # no second account


def test_login_sends_no_sms(settings):
    app, _, provider, _ = _app(settings)
    with TestClient(app) as client:
        signup = _signup_request(client)
        user_id = signup.json()["user_id"]
        client.post("/auth/verify/phone", json={"user_id": user_id, "code": "111111"})
        client.post("/auth/verify/email", json={"user_id": user_id, "code": "222222"})
        before = provider.deliveries
        response = client.post(
            "/auth/login",
            json={
                "identifier": "sipho@example.com",
                "password": PASSWORD,
                "turnstile_token": "fixture-token",
            },
        )
        assert response.status_code == 200
    assert provider.deliveries == before


def test_unverified_user_blocked(settings):
    app, _, _, _ = _app(settings)
    with TestClient(app) as client:
        signup = _signup_request(client)
        user_id = signup.json()["user_id"]
        client.post("/auth/verify/phone", json={"user_id": user_id, "code": "111111"})
        # Phone-only verified: login must still be refused (email step incomplete).
        blocked = client.post(
            "/auth/login",
            json={
                "identifier": "sipho@example.com",
                "password": PASSWORD,
                "turnstile_token": "fixture-token",
            },
        )
        assert blocked.status_code == 401


def test_idempotency_key_replays_the_original_signup_response(settings):
    app, _, provider, sessions = _app(settings)
    with TestClient(app) as client:
        headers = {"Idempotency-Key": "test-signup-key-0001"}
        first = client.post("/auth/signup", json=_signup_body(), headers=headers)
        second = client.post("/auth/signup", json=_signup_body(), headers=headers)
        assert first.status_code == second.status_code == 200
        assert first.json() == second.json()
    assert provider.deliveries == 1  # only the first request actually sent an OTP
    with sessions() as session:
        assert len(session.scalars(select(AuthIdentity)).all()) == 1  # no second account


def test_idempotency_key_reuse_with_different_payload_is_rejected(settings):
    app, _, _, _ = _app(settings)
    with TestClient(app) as client:
        headers = {"Idempotency-Key": "test-signup-key-0002"}
        first = client.post("/auth/signup", json=_signup_body(), headers=headers)
        assert first.status_code == 200
        conflict = client.post(
            "/auth/signup", json=_signup_body(phone="+27820000002"), headers=headers
        )
        assert conflict.status_code == 409
        assert conflict.json()["error"]["code"] == "idempotency_key_conflict"


def test_signup_requires_idempotency_key(settings):
    app, _, _, sessions = _app(settings)
    with TestClient(app) as client:
        response = client.post("/auth/signup", json=_signup_body())
    assert response.status_code == 400
    assert response.json()["error"]["code"] == "idempotency_key_required"
    with sessions() as session:
        assert session.scalar(select(AuthIdentity)) is None


def test_idempotency_claim_blocks_duplicate_until_completion(settings):
    from farmable_backend.idempotency import (
        IdempotencyInProgress,
        claim,
        store,
    )

    _, _, _, sessions = _app(settings)
    kwargs = {
        "route": "test_claim",
        "scope": "scope",
        "key": "test-claim-key-0001",
        "request_fingerprint": "a" * 64,
    }
    assert claim(sessions, **kwargs) is None
    with pytest.raises(IdempotencyInProgress):
        claim(sessions, **kwargs)
    store(sessions, **kwargs, status_code=200, body={"ok": True})
    assert claim(sessions, **kwargs) == (200, {"ok": True})


def test_turnstile_down_refuses(settings):
    engine = _engine()
    sessions = sessionmaker(engine, expire_on_commit=False)
    provider = CountingOtpProvider()
    auth = AuthService(sessions, provider)
    app = create_app(
        settings,
        readiness=lambda: {},
        service_settings=ServiceSettings(
            environment="ci", integrations_mode="fake", fault_turnstile=True
        ),
    )
    app.state.auth = auth
    app.state.services = ServiceRegistry(
        ServiceSettings(environment="ci", integrations_mode="fake", fault_turnstile=True)
    )
    with TestClient(app) as client:
        response = _signup_request(client)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "turnstile_failed"
    assert provider.deliveries == 0
    with sessions() as session:
        assert session.scalar(select(AuthIdentity)) is None
        assert session.scalar(select(User)) is None
        assert session.scalar(select(Farm)) is None
