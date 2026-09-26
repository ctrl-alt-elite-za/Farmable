"""Live sign-up codes through Twilio Verify (real SMS and email OTPs)."""

from urllib.parse import parse_qs

import httpx
import pytest
from farmable_backend.auth import AuthError, AuthService, Channel, SessionTokens
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.models import (
    AuthIdentity,
    AuthSession,
    Base,
    Farm,
    User,
    VerificationChallenge,
)
from farmable_backend.twilio_otp import TwilioVerifyOtpProvider, create_live_otp_provider
from sqlalchemy import create_engine, select
from sqlalchemy.orm import sessionmaker

PASSWORD = "correct horse battery staple"  # noqa: S105 - synthetic test credential
ACCOUNT = "AC" + "1" * 32
SERVICE = "VA" + "2" * 32
TOKEN = "fake-token"  # noqa: S105 - synthetic test credential


class FakeVerify:
    """Twilio Verify's two endpoints: one pending code per destination."""

    def __init__(self, code="123456"):
        self.code = code
        self.sent: list[tuple[str, str]] = []
        self.pending: set[str] = set()
        self.fail: int | None = None

    def __call__(self, request: httpx.Request) -> httpx.Response:
        assert request.url.host == "verify.twilio.com"
        assert request.url.path.startswith(f"/v2/Services/{SERVICE}/")
        assert request.headers["authorization"].startswith("Basic ")
        if self.fail is not None:
            return httpx.Response(self.fail, json={"message": "nope"})
        form = {k: v[0] for k, v in parse_qs(request.content.decode()).items()}
        if request.url.path.endswith("/Verifications"):
            self.sent.append((form["Channel"], form["To"]))
            self.pending.add(form["To"])
            return httpx.Response(201, json={"status": "pending"})
        if form["To"] not in self.pending:
            return httpx.Response(404, json={"code": 20404})
        if form["Code"] != self.code:
            return httpx.Response(200, json={"status": "pending"})
        self.pending.discard(form["To"])
        return httpx.Response(200, json={"status": "approved"})


def provider(verify: FakeVerify) -> TwilioVerifyOtpProvider:
    return TwilioVerifyOtpProvider(ACCOUNT, SERVICE, TOKEN, transport=httpx.MockTransport(verify))


def service(verify: FakeVerify):
    engine = create_engine("sqlite://")
    Base.metadata.create_all(
        engine,
        tables=[
            User.__table__,
            Farm.__table__,
            AuthIdentity.__table__,
            VerificationChallenge.__table__,
            AuthSession.__table__,
        ],
    )
    sessions = sessionmaker(engine, expire_on_commit=False)
    return sessions, AuthService(sessions, provider(verify))


def test_sign_up_sends_a_real_sms_then_a_real_email_code():
    verify = FakeVerify()
    _sessions, auth = service(verify)
    user = auth.signup("Sipho", "Dlamini", "+27821234567", "Sipho@Example.com", PASSWORD)
    assert verify.sent == [("sms", "+27821234567")]

    auth.verify(user.id, Channel.PHONE, "123456")
    assert verify.sent[-1] == ("email", "sipho@example.com")

    tokens = auth.verify(user.id, Channel.EMAIL, "123456")
    assert isinstance(tokens, SessionTokens)
    assert tokens.user.phone_verified and tokens.user.email_verified


def test_a_wrong_code_counts_as_an_attempt_and_stores_no_twilio_code():
    verify = FakeVerify()
    sessions, auth = service(verify)
    user = auth.signup("Sipho", "Dlamini", "+27821234567", "sipho@example.com", PASSWORD)

    with pytest.raises(AuthError, match="invalid_verification"):
        auth.verify(user.id, Channel.PHONE, "000000")
    with pytest.raises(AuthError, match="invalid_verification"):
        auth.verify(user.id, Channel.PHONE, "not-a-code")

    with sessions() as session:
        challenge = session.scalar(select(VerificationChallenge))
        assert challenge is not None and challenge.attempts == 2
        # The stored hash is of a random placeholder, never of Twilio's code.
        assert not AuthService._verify_code(challenge.code_hash, "123456")


def test_an_expired_twilio_verification_is_an_invalid_code_not_an_outage():
    verify = FakeVerify()
    _sessions, auth = service(verify)
    user = auth.signup("Sipho", "Dlamini", "+27821234567", "sipho@example.com", PASSWORD)
    verify.pending.clear()
    with pytest.raises(AuthError, match="invalid_verification"):
        auth.verify(user.id, Channel.PHONE, "123456")


@pytest.mark.parametrize(
    ("status", "code", "http"),
    [(500, "provider_error", 503), (400, "provider_error", 503), (429, "otp_rate_limited", 429)],
)
def test_twilio_errors_fail_sign_up_cleanly(status, code, http):
    verify = FakeVerify()
    verify.fail = status
    sessions, auth = service(verify)
    with pytest.raises(AuthError, match=code) as raised:
        auth.signup("Sipho", "Dlamini", "+27821234567", "sipho@example.com", PASSWORD)
    assert raised.value.status_code == http
    with sessions() as session:
        # The whole sign-up rolls back, so the farmer can simply try again.
        assert session.scalar(select(AuthIdentity)) is None


def test_an_unreachable_twilio_is_reported_as_unavailable():
    def down(request):
        raise httpx.ConnectError("down", request=request)

    otp = TwilioVerifyOtpProvider(ACCOUNT, SERVICE, TOKEN, transport=httpx.MockTransport(down))
    with pytest.raises(AuthError, match="provider_unavailable"):
        otp.deliver(Channel.PHONE, "+27821234567", "ignored")


def live(**overrides) -> ServiceSettings:
    values = {
        "environment": "staging",
        "integrations_mode": "live",
        "twilio_account_sid": ACCOUNT,
        "twilio_verify_service_sid": SERVICE,
        "twilio_auth_token": TOKEN,
        "twilio_fraud_guard_confirmed": True,
    }
    return ServiceSettings(**(values | overrides))


def test_live_codes_need_every_twilio_setting_and_the_fraud_guard():
    otp = create_live_otp_provider(live())
    assert isinstance(otp, TwilioVerifyOtpProvider)
    otp.close()
    assert create_live_otp_provider(live(twilio_fraud_guard_confirmed=False)) is None
    assert create_live_otp_provider(live(twilio_auth_token=None)) is None
    assert create_live_otp_provider(live(twilio_verify_service_sid=None)) is None
    assert create_live_otp_provider(live(integrations_mode="disabled")) is None
