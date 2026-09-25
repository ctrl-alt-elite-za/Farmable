"""Authentication domain service. OTP plaintext exists only at fake-provider delivery time."""

from __future__ import annotations

import hashlib
import logging
import secrets
from asyncio import AbstractEventLoop, run_coroutine_threadsafe
from concurrent.futures import TimeoutError as FuturesTimeoutError
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import Enum
from typing import Protocol, TypedDict
from uuid import UUID, uuid4

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.email_templates import notification_email, otp_email
from farmable_backend.idempotency import IN_PROGRESS_STATUS
from farmable_backend.integrations.email.base import DeliveryUnknown, EmailSender
from farmable_backend.integrations.infobip import Infobip
from farmable_backend.models import (
    AuthIdentity,
    AuthSession,
    Farm,
    IdempotencyRecord,
    User,
    VerificationChallenge,
)
from farmable_backend.rate_limits import (
    RateLimited,
    admit_login,
    finish_login,
    retry_after_if_limited,
)
from farmable_backend.rate_limits import check as rate_check

PASSWORD_HASHER = PasswordHasher()  # argon2-cffi defaults are Argon2id.
# Unknown accounts must still pay the same Argon2 verification cost as known
# accounts; otherwise login latency becomes an account-enumeration oracle.
DUMMY_PASSWORD_HASH = PASSWORD_HASHER.hash(secrets.token_urlsafe(32))
OTP_TTL = timedelta(minutes=10)
ACCESS_TTL = timedelta(minutes=15)
SESSION_TTL = timedelta(days=30)
MAX_OTP_ATTEMPTS = 5
OTP_SEND_WINDOW = timedelta(minutes=10)
MAX_OTP_SENDS = 3
DEFAULT_FARM_NAME = "My farm"

# Small curated set of extremely common passwords/patterns (#9 security
# criteria). Not exhaustive; a fuller list is a follow-up, not a #9 blocker,
# since the 15-char minimum already rules out most of the canonical top-10k.
COMMON_PASSWORDS = frozenset(
    {
        "password123456",
        "letmein12345678",
        "qwertyuiop12345",
        "123456789012345",
        "iloveyou1234567",
        "welcome123456789",
        "changeme1234567",
        "administrator1",
        "passwordpassword",
        "trustno1trustno1",
    }
)


def _rate_limit(sessions: sessionmaker[Session], **kwargs: object) -> None:
    # Its own short, immediately-committing transaction (see rate_limits.py)
    # — never nested inside the caller's own signup/login/_send transaction,
    # so the row lock never blocks on password hashing, inserts, or an OTP
    # provider call.
    try:
        rate_check(sessions, **kwargs)  # type: ignore[arg-type]
    except RateLimited as exc:
        raise AuthError(exc.code, 429, exc.retry_after) from exc


def check_sms_limits(sessions: sessionmaker[Session], *, ip: str, phone: str) -> None:
    """Admit one SMS across IP, destination and global budgets."""
    _rate_limit(
        sessions,
        scope="sms_ip",
        subject=ip,
        window_seconds=3600,
        limit=10,
        code="sms_ip_rate_limited",
    )
    _rate_limit(
        sessions,
        scope="sms_phone",
        subject=phone,
        window_seconds=600,
        limit=3,
        code="sms_phone_rate_limited",
    )
    _rate_limit(
        sessions,
        scope="sms_daily",
        subject="global",
        window_seconds=86400,
        limit=50,
        code="daily_sms_cap",
    )


def check_email_limits(sessions: sessionmaker[Session], *, ip: str, email: str) -> None:
    """Admit one email OTP across IP, destination and global budgets."""
    _rate_limit(
        sessions,
        scope="email_ip",
        subject=ip,
        window_seconds=3600,
        limit=10,
        code="email_ip_rate_limited",
    )
    _rate_limit(
        sessions,
        scope="email_address",
        subject=email,
        window_seconds=600,
        limit=3,
        code="email_address_rate_limited",
    )
    _rate_limit(
        sessions,
        scope="email_daily",
        subject="global",
        window_seconds=86400,
        limit=50,
        code="daily_email_cap",
    )


class AuthError(Exception):
    def __init__(
        self,
        code: str,
        status_code: int = 400,
        retry_after: int | None = None,
        user_id: UUID | None = None,
    ):
        self.code = code
        self.status_code = status_code
        self.retry_after = retry_after
        self.user_id = user_id
        super().__init__(code)


class Channel(str, Enum):
    PHONE = "phone"
    EMAIL = "email"


@dataclass(frozen=True)
class AuthUser:
    id: UUID
    first_name: str
    surname: str
    phone: str
    email: str
    phone_verified: bool
    email_verified: bool


@dataclass(frozen=True)
class SessionTokens:
    access_token: str
    refresh_token: str
    expires_at: datetime
    refresh_expires_at: datetime
    user: AuthUser


class OtpProvider(Protocol):
    def create_code(self, channel: Channel) -> str: ...

    def deliver(self, channel: Channel, destination: str, code: str) -> None: ...

    def notify_existing_account(self, channel: Channel, destination: str) -> None: ...


class DeterministicFakeOtpProvider:
    """Test/development provider. It deliberately retains no OTP values or logs."""

    codes = {Channel.PHONE: "111111", Channel.EMAIL: "222222"}

    def create_code(self, channel: Channel) -> str:
        return self.codes[channel]

    def deliver(self, channel: Channel, destination: str, code: str) -> None:
        if code != self.codes[channel]:
            raise AuthError("provider_error", 503)

    def notify_existing_account(self, channel: Channel, destination: str) -> None:
        pass  # Test/dev provider: no delivery log kept for this either.


class DisabledOtpProvider:
    """Fail closed until a live SMS and email adapter is configured and wired."""

    def create_code(self, channel: Channel) -> str:
        return f"{secrets.randbelow(1_000_000):06d}"

    def deliver(self, channel: Channel, destination: str, code: str) -> None:
        raise AuthError("provider_unavailable", 503)

    def notify_existing_account(self, channel: Channel, destination: str) -> None:
        raise AuthError("provider_unavailable", 503)


EMAIL_DAILY_CAP_SCOPE = "email_daily_cap"
EMAIL_DAILY_CAP_WARNING_THRESHOLD = 400
EMAIL_DAILY_CAP_LIMIT = 500


class LiveOtpProvider:
    """Live delivery: SMS via Infobip, email via a pluggable ``EmailSender``.

    OtpProvider methods run synchronously on the auth thread pool. SMS goes
    through the shared async Infobip adapter (its httpx client/circuit
    breaker lives on the main asyncio event loop); ``run_coroutine_threadsafe``
    bridges the two without a second event loop or connection pool. Email is
    synchronous SMTP and is called directly - no bridging needed.
    """

    def __init__(
        self,
        infobip: Infobip,
        email_sender: EmailSender,
        loop: AbstractEventLoop,
        sessions: sessionmaker[Session],
    ):
        self._infobip = infobip
        self._email_sender = email_sender
        self._loop = loop
        self._sessions = sessions

    def create_code(self, channel: Channel) -> str:
        return f"{secrets.randbelow(1_000_000):06d}"

    def _send_sms(self, destination: str, text: str) -> None:
        future = run_coroutine_threadsafe(self._infobip.send_sms(destination, text), self._loop)
        # Adapter.call() bounds itself to at most max_attempts * timeout plus
        # backoff sleeps between attempts; the bridge timeout must cover that
        # whole worst case, or a mid-retry request would raise an untranslated
        # TimeoutError here while the coroutine keeps running on the main loop.
        budget = self._infobip.timeout * self._infobip.max_attempts + 10
        try:
            result = future.result(timeout=budget)
        except FuturesTimeoutError as error:
            raise AuthError("delivery_unknown", 503) from error
        if not result.ok:
            raise AuthError("delivery_unknown" if result.ambiguous else "provider_unavailable", 503)

    def _send_email(self, destination: str, subject: str, html: str, text: str) -> None:
        # Reuses the existing durable rate-limit counter table (no schema
        # change) purely to track/cap Gmail's daily send volume; unrelated to
        # the per-account/IP abuse limits enforced upstream of this provider.
        try:
            rate_check(
                self._sessions,
                scope=EMAIL_DAILY_CAP_SCOPE,
                subject="global",
                window_seconds=86400,
                limit=EMAIL_DAILY_CAP_LIMIT,
                code="email_daily_cap",
            )
        except RateLimited as error:
            raise AuthError("provider_unavailable", 503) from error
        count = retry_after_if_limited(
            self._sessions,
            scope=EMAIL_DAILY_CAP_SCOPE,
            subject="global",
            window_seconds=86400,
            limit=EMAIL_DAILY_CAP_WARNING_THRESHOLD,
        )
        if count is not None:
            logging.getLogger(__name__).warning("Approaching the Gmail daily send limit")
        try:
            sent = self._email_sender.send(destination, subject, html, text)
        except DeliveryUnknown as error:
            raise AuthError("delivery_unknown", 503) from error
        if not sent:
            raise AuthError("provider_unavailable", 503)

    def deliver(self, channel: Channel, destination: str, code: str) -> None:
        if channel is Channel.PHONE:
            self._send_sms(
                destination, f"Your Almanac verification code is {code}. It expires in 10 minutes."
            )
        else:
            html, text = otp_email(code)
            self._send_email(destination, "Your Almanac verification code", html, text)

    def notify_existing_account(self, channel: Channel, destination: str) -> None:
        if channel is Channel.PHONE:
            self._send_sms(
                destination,
                "Someone tried to sign up for Almanac with this phone number. "
                "If this wasn't you, no action is needed.",
            )
        else:
            html, text = notification_email(
                "Almanac sign-up attempt",
                "Someone tried to sign up for Almanac with this email address. "
                "If this wasn't you, no action is needed.",
            )
            self._send_email(destination, "Almanac sign-up attempt", html, text)


class _MemoryUser(TypedDict):
    first_name: str
    surname: str
    phone: str
    email: str
    password_hash: str
    phone_verified: bool
    email_verified: bool


def _now() -> datetime:
    return datetime.now(UTC)


def _as_utc(value: datetime) -> datetime:
    return value.replace(tzinfo=UTC) if value.tzinfo is None else value.astimezone(UTC)


def _hash_token(value: str) -> str:
    return hashlib.sha256(value.encode()).hexdigest()


def _user(model: AuthIdentity) -> AuthUser:
    if not all((model.first_name, model.surname, model.phone, model.email)):
        raise AuthError("invalid_credentials", 401)
    return AuthUser(
        model.id,
        model.first_name,
        model.surname,
        model.phone,
        model.email,
        model.phone_verified,
        model.email_verified,
    )


class AuthService:
    def __init__(self, sessions: sessionmaker[Session], provider: OtpProvider | None = None):
        self.sessions = sessions
        self.provider = provider or DisabledOtpProvider()

    def signup(
        self,
        first_name: str,
        surname: str,
        phone: str,
        email: str,
        password: str,
        *,
        ip: str = "unknown",
        idempotency_key: str | None = None,
        idempotency_scope: str = "",
    ) -> AuthUser:
        email = email.strip().lower()
        phone = phone.strip()
        if password.lower() in COMMON_PASSWORDS:
            raise AuthError("password_too_common", 422)
        # A fabricated, never-persisted identity: returned on an existing-email/
        # phone collision so the response is shaped identically to a genuine
        # sign-up without creating a second account or a fake DB row (#9
        # enumeration resistance).
        placeholder = AuthUser(
            uuid4(), first_name.strip(), surname.strip(), phone, email, False, False
        )
        # Its own short transaction, committed before the (possibly slow)
        # work below even starts — see rate_limits.py.
        _rate_limit(
            self.sessions,
            scope="signup_ip",
            subject=ip,
            window_seconds=3600,
            limit=5,
            code="signup_rate_limited",
        )
        # Signup always sends exactly one phone OTP; check its cost-abuse
        # limits upfront too, so a rejection here never leaves an orphaned
        # owner/identity/farm row from a transaction rolled back mid-flight.
        self._check_sms_limits(ip, phone)
        with self.sessions.begin() as session:
            existing = session.scalar(
                select(AuthIdentity).where(
                    (AuthIdentity.email == email) | (AuthIdentity.phone == phone)
                )
            )
            if existing is not None:
                self._notify_collision(existing, email, phone)
                # Same public response/status as a new sign-up; no OTP is
                # sent to the caller, and no account, farm, challenge, or
                # session is created or mutated for this request.
                return placeholder
            password_hash = PASSWORD_HASHER.hash(password)
            try:
                with session.begin_nested():
                    owner = User()
                    session.add(owner)
                    session.flush()
                    user = AuthIdentity(
                        id=owner.id,
                        first_name=first_name.strip(),
                        surname=surname.strip(),
                        phone=phone,
                        email=email,
                        password_hash=password_hash,
                    )
                    session.add(user)
                    # Claim the unique credentials before delivering an OTP;
                    # owner+identity+farm share this savepoint, so a
                    # credential conflict rolls all three back together
                    # without touching the rate-limit hit recorded above.
                    session.flush()
                    # Issue #9: every account owns exactly one empty farm
                    # from sign-up, so the account API always has a subject.
                    session.add(Farm(owner_id=owner.id, name=DEFAULT_FARM_NAME))
                    session.flush()
            except IntegrityError as exc:
                diagnostic = getattr(exc.orig, "diag", None)
                if getattr(exc.orig, "sqlstate", None) == "23505" and getattr(
                    diagnostic, "constraint_name", None
                ) in {"uq_auth_identities_email", "uq_auth_identities_phone"}:
                    # Lost a race against a concurrent sign-up claiming the
                    # same email/phone. Same enumeration-safe response as the
                    # pre-check, and the same best-effort owner warning.
                    winner = session.scalar(
                        select(AuthIdentity).where(
                            (AuthIdentity.email == email) | (AuthIdentity.phone == phone)
                        )
                    )
                    if winner is not None:
                        self._notify_collision(winner, email, phone)
                    return placeholder
                raise
            if idempotency_key is not None:
                # The provisional user ID is committed atomically with the
                # account and OTP challenge. If the request worker dies
                # before the outer handler can store the final response, a
                # later retry can still recover this exact account without
                # sending another OTP.
                claim = session.get(
                    IdempotencyRecord,
                    ("auth_signup", idempotency_scope, idempotency_key),
                    with_for_update=True,
                )
                if claim is not None and claim.status_code == IN_PROGRESS_STATUS:
                    claim.response_body = {"user_id": str(user.id)}
            failure = self._send(session, user, Channel.PHONE)
            result = _user(user)
        if failure is not None:
            raise AuthError(
                failure.code,
                failure.status_code,
                failure.retry_after,
                user_id=user.id,
            )
        return result

    def _notify_collision(self, existing: AuthIdentity, email: str, phone: str) -> None:
        # Best-effort: the real owner is warned that someone tried to sign up
        # with their email/phone. Never lets a provider failure change the
        # public response — that must stay identical to a new sign-up either
        # way (#9 enumeration resistance).
        for channel, destination, matched in (
            (Channel.EMAIL, existing.email, existing.email == email),
            (Channel.PHONE, existing.phone, existing.phone == phone),
        ):
            if not matched:
                continue
            try:
                self.provider.notify_existing_account(channel, destination)
            except AuthError:
                pass

    def verify(self, user_id: UUID, channel: Channel, code: str) -> AuthUser | SessionTokens:
        failure: AuthError | None = None
        result: AuthUser | SessionTokens | None = None
        with self.sessions.begin() as session:
            user = session.scalar(
                select(AuthIdentity).where(AuthIdentity.id == user_id).with_for_update()
            )
            if user is None:
                raise AuthError("invalid_verification", 400)
            challenge = session.scalar(
                select(VerificationChallenge)
                .where(
                    VerificationChallenge.user_id == user_id,
                    VerificationChallenge.channel == channel,
                    VerificationChallenge.consumed_at.is_(None),
                )
                .order_by(VerificationChallenge.created_at.desc())
                .with_for_update()
            )
            if (
                challenge is None
                or _as_utc(challenge.expires_at) <= _now()
                or challenge.attempts >= MAX_OTP_ATTEMPTS
            ):
                raise AuthError("invalid_verification", 400)
            if not self._verify_code(challenge.code_hash, code):
                challenge.attempts += 1
                failure = AuthError("invalid_verification", 400)
            else:
                challenge.consumed_at = _now()
                if channel is Channel.PHONE:
                    user.phone_verified = True
                    self._send(session, user, Channel.EMAIL)
                    result = _user(user)
                elif not user.phone_verified:
                    failure = AuthError("invalid_verification", 400)
                else:
                    user.email_verified = True
                    result = self._new_session(session, user)
        if failure is not None:
            raise failure
        if result is None:  # Defensive: every successful branch assigns a result.
            raise AuthError("invalid_verification", 400)
        return result

    def resend(
        self,
        user_id: UUID,
        channel: Channel,
        *,
        ip: str = "unknown",
        idempotency_key: str | None = None,
    ) -> None:
        failure: AuthError | None = None
        with self.sessions.begin() as session:
            user = session.scalar(
                select(AuthIdentity).where(AuthIdentity.id == user_id).with_for_update()
            )
            if user is None or (channel is Channel.EMAIL and not user.phone_verified):
                raise AuthError("invalid_verification", 400)
            if (channel is Channel.PHONE and user.phone_verified) or (
                channel is Channel.EMAIL and user.email_verified
            ):
                raise AuthError("invalid_verification", 400)
            if channel is Channel.PHONE:
                self._check_sms_limits(ip, user.phone)
            failure = self._send(session, user, channel)
            if idempotency_key is not None:
                claim = session.get(
                    IdempotencyRecord,
                    ("auth_otp_resend", str(user_id), idempotency_key),
                    with_for_update=True,
                )
                if claim is not None and claim.status_code == IN_PROGRESS_STATUS:
                    # Commit the replay outcome with the new challenge. A
                    # response-store failure or worker exit after this commit
                    # must not let the same key dispatch a second message.
                    claim.status_code = failure.status_code if failure is not None else 204
                    claim.response_body = (
                        {"error": {"code": failure.code, "retry_after": failure.retry_after}}
                        if failure is not None
                        else {}
                    )
        if failure is not None:
            raise failure

    def login(self, identifier: str, password: str, *, ip: str = "unknown") -> SessionTokens:
        identifier = identifier.strip()
        normalized_identifier = identifier.lower()
        try:
            reservation = admit_login(self.sessions, account=normalized_identifier, ip=ip)
        except RateLimited as exc:
            raise AuthError(exc.code, 429, exc.retry_after) from exc
        failure: AuthError | None = None
        result: SessionTokens | None = None
        with self.sessions.begin() as session:
            user = session.scalar(
                select(AuthIdentity).where(
                    (AuthIdentity.email == identifier.lower()) | (AuthIdentity.phone == identifier)
                )
            )
            password_hash = (
                user.password_hash
                if user is not None and user.password_hash is not None
                else DUMMY_PASSWORD_HASH
            )
            password_valid = self._verify_password(password_hash, password)
            verified = user is not None and (user.phone_verified and user.email_verified)
            valid = (
                user is not None and user.password_hash is not None and password_valid and verified
            )
            still_admitted = finish_login(
                session,
                account=normalized_identifier,
                ip=ip,
                success=valid,
                reservation=reservation,
            )
            if not valid:
                failure = (
                    AuthError("invalid_credentials", 401)
                    if still_admitted
                    else AuthError("login_rate_limited", 429, 900)
                )
            elif not still_admitted:
                failure = AuthError("login_rate_limited", 429, 900)
            else:
                if user is None:
                    raise AuthError("invalid_credentials", 401)
                result = self._new_session(session, user)
        if failure is not None:
            # Reservation finalization and session insertion share this
            # transaction, so a fenced success can never issue a token.
            raise failure
        if result is None:
            raise AuthError("invalid_credentials", 401)
        return result

    def refresh(self, refresh_token: str) -> SessionTokens:
        # A raise inside `with self.sessions.begin()` rolls the whole
        # transaction back — including the cascade-revoke UPDATE below. So
        # every branch here sets `failure`/`result` and exits the block
        # normally (committing), then raises afterwards if needed, mirroring
        # `verify()`'s pattern.
        failure: AuthError | None = None
        result: SessionTokens | None = None
        with self.sessions.begin() as session:
            token_hash = _hash_token(refresh_token)
            # Lock the session row (if any) so a concurrent refresh with the
            # same token serializes instead of both racing the reuse check.
            existing = session.scalar(
                select(AuthSession)
                .where(AuthSession.refresh_token_hash == token_hash)
                .with_for_update()
            )
            if existing is None:
                failure = AuthError("invalid_session", 401)
            elif existing.revoked_at is not None:
                # Reuse of an already-rotated/revoked refresh token: treat as
                # theft and revoke every live session for this user.
                session.execute(
                    update(AuthSession)
                    .where(
                        AuthSession.user_id == existing.user_id,
                        AuthSession.revoked_at.is_(None),
                    )
                    .values(revoked_at=_now())
                )
                failure = AuthError("invalid_session", 401)
            elif _as_utc(existing.expires_at) <= _now():
                failure = AuthError("invalid_session", 401)
            else:
                existing.revoked_at = _now()
                user = session.get(AuthIdentity, existing.user_id)
                if user is None or not (user.phone_verified and user.email_verified):
                    failure = AuthError("invalid_session", 401)
                else:
                    result = self._new_session(session, user)
        if failure is not None:
            raise failure
        if result is None:  # Defensive: every successful branch assigns a result.
            raise AuthError("invalid_session", 401)
        return result

    def _check_sms_limits(self, ip: str, phone: str) -> None:
        # SMS costs money per send (~$0.19); gate on IP and a system-wide
        # daily cap. Called by signup()/resend() *before* their own
        # transaction opens (and before _send() is reached), so a rejection
        # here never leaves an orphaned owner/identity/farm row, and the
        # provider is never called. Each check is its own short,
        # already-committed transaction (see rate_limits.py).
        check_sms_limits(self.sessions, ip=ip, phone=phone)

    def _send(
        self,
        session: Session,
        user: AuthIdentity,
        channel: Channel,
    ) -> AuthError | None:
        recent = session.scalars(
            select(VerificationChallenge).where(
                VerificationChallenge.user_id == user.id,
                VerificationChallenge.channel == channel,
                VerificationChallenge.created_at > _now() - OTP_SEND_WINDOW,
            )
        ).all()
        if len(recent) >= MAX_OTP_SENDS:
            oldest = min(c.created_at for c in recent)
            retry = max(1, int((_as_utc(oldest) + OTP_SEND_WINDOW - _now()).total_seconds()) + 1)
            raise AuthError("otp_rate_limited", 429, retry)
        session.execute(
            update(VerificationChallenge)
            .where(
                VerificationChallenge.user_id == user.id,
                VerificationChallenge.channel == channel,
                VerificationChallenge.consumed_at.is_(None),
            )
            .values(consumed_at=_now())
        )
        code = self.provider.create_code(channel)
        try:
            self.provider.deliver(
                channel, user.phone if channel is Channel.PHONE else user.email, code
            )
        except AuthError as error:
            if error.code != "delivery_unknown":
                raise
            session.add(
                VerificationChallenge(
                    user_id=user.id,
                    channel=channel.value,
                    code_hash=PASSWORD_HASHER.hash(code),
                    expires_at=_now() + OTP_TTL,
                )
            )
            return error
        session.add(
            VerificationChallenge(
                user_id=user.id,
                channel=channel.value,
                code_hash=PASSWORD_HASHER.hash(code),
                expires_at=_now() + OTP_TTL,
            )
        )
        return None

    def _new_session(self, session: Session, user: AuthIdentity) -> SessionTokens:
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
        issued_at = _now()
        access_expires_at = issued_at + ACCESS_TTL
        refresh_expires_at = issued_at + SESSION_TTL
        session.add(
            AuthSession(
                user_id=user.id,
                access_token_hash=_hash_token(access),
                refresh_token_hash=_hash_token(refresh),
                expires_at=refresh_expires_at,
            )
        )
        return SessionTokens(access, refresh, access_expires_at, refresh_expires_at, _user(user))

    @staticmethod
    def _verify_password(password_hash: str, password: str) -> bool:
        try:
            return PASSWORD_HASHER.verify(password_hash, password)
        except (VerificationError, InvalidHashError):
            return False

    @staticmethod
    def _verify_code(code_hash: str, code: str) -> bool:
        try:
            return PASSWORD_HASHER.verify(code_hash, code)
        except (VerificationError, InvalidHashError):
            return False


class InMemoryAuthService:
    """Deterministic test adapter that follows the same externally visible contract."""

    def __init__(self) -> None:
        self.users: dict[UUID, _MemoryUser] = {}
        self.otp: dict[tuple[UUID, Channel], str] = {}
        self.sessions: dict[str, UUID] = {}
        self.deliveries: list[tuple[Channel, UUID]] = []

    def signup(
        self,
        first_name: str,
        surname: str,
        phone: str,
        email: str,
        password: str,
        *,
        ip: str = "unknown",
        idempotency_key: str | None = None,
        idempotency_scope: str = "",
    ) -> AuthUser:
        del idempotency_key, idempotency_scope
        if any(u["email"] == email.lower() or u["phone"] == phone for u in self.users.values()):
            # #9 enumeration resistance: identical shape to a new sign-up, no
            # account/OTP created or sent for this request.
            return AuthUser(
                uuid4(), first_name.strip(), surname.strip(), phone, email.lower(), False, False
            )
        user_id = uuid4()
        self.users[user_id] = {
            "first_name": first_name,
            "surname": surname,
            "phone": phone,
            "email": email.lower(),
            "password_hash": PASSWORD_HASHER.hash(password),
            "phone_verified": False,
            "email_verified": False,
        }
        self.otp[user_id, Channel.PHONE] = "111111"
        self.deliveries.append((Channel.PHONE, user_id))
        return self._as_user(user_id)

    def verify(self, user_id: UUID, channel: Channel, code: str) -> AuthUser | SessionTokens:
        user = self.users.get(user_id)
        if user is None or self.otp.get((user_id, channel)) != code:
            raise AuthError("invalid_verification", 400)
        self.otp.pop((user_id, channel))
        if channel is Channel.PHONE:
            user["phone_verified"] = True
            self.otp[user_id, Channel.EMAIL] = "222222"
            self.deliveries.append((Channel.EMAIL, user_id))
            return self._as_user(user_id)
        if not user["phone_verified"]:
            raise AuthError("invalid_verification", 400)
        user["email_verified"] = True
        return self._new_session(user_id)

    def login(self, identifier: str, password: str, *, ip: str = "unknown") -> SessionTokens:
        user_id = next(
            (
                key
                for key, u in self.users.items()
                if (u["email"] == identifier.lower() or u["phone"] == identifier)
                and self._verify_password(u["password_hash"], password)
            ),
            None,
        )
        if user_id is None:
            raise AuthError("invalid_credentials", 401)
        user = self.users[user_id]
        if not user["phone_verified"] or not user["email_verified"]:
            raise AuthError("invalid_credentials", 401)
        return self._new_session(user_id)

    def refresh(self, refresh_token: str) -> SessionTokens:
        user_id = self.sessions.pop(_hash_token(refresh_token), None)
        if user_id is None:
            raise AuthError("invalid_session", 401)
        return self._new_session(user_id)

    def _new_session(self, user_id: UUID) -> SessionTokens:
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
        issued_at = _now()
        access_expires_at = issued_at + ACCESS_TTL
        refresh_expires_at = issued_at + SESSION_TTL
        self.sessions[_hash_token(refresh)] = user_id
        return SessionTokens(
            access, refresh, access_expires_at, refresh_expires_at, self._as_user(user_id)
        )

    def resend(
        self,
        user_id: UUID,
        channel: Channel,
        *,
        ip: str = "unknown",
        idempotency_key: str | None = None,
    ) -> None:
        user = self.users.get(user_id)
        if user is None or (channel is Channel.EMAIL and not user["phone_verified"]):
            raise AuthError("invalid_verification", 400)
        self.otp[user_id, channel] = DeterministicFakeOtpProvider.codes[channel]
        self.deliveries.append((channel, user_id))

    @staticmethod
    def _verify_password(password_hash: str, password: str) -> bool:
        try:
            return PASSWORD_HASHER.verify(password_hash, password)
        except (VerificationError, InvalidHashError):
            return False

    def _as_user(self, user_id: UUID) -> AuthUser:
        item = self.users[user_id]
        return AuthUser(
            user_id,
            item["first_name"],
            item["surname"],
            item["phone"],
            item["email"],
            item["phone_verified"],
            item["email_verified"],
        )
