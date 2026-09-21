"""Authentication domain service. OTP plaintext exists only at fake-provider delivery time."""

from __future__ import annotations

import hashlib
import secrets
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from enum import Enum
from typing import Protocol, TypedDict
from uuid import UUID, uuid4

from argon2 import PasswordHasher
from argon2.exceptions import InvalidHashError, VerificationError
from sqlalchemy import select, update
from sqlalchemy.orm import Session, sessionmaker

from farmable_backend.models import AuthSession, User, VerificationChallenge

PASSWORD_HASHER = PasswordHasher()  # argon2-cffi defaults are Argon2id.
OTP_TTL = timedelta(minutes=10)
SESSION_TTL = timedelta(days=30)
MAX_OTP_ATTEMPTS = 5
OTP_SEND_WINDOW = timedelta(minutes=10)
MAX_OTP_SENDS = 3


class AuthError(Exception):
    def __init__(self, code: str, status_code: int = 400):
        self.code = code
        self.status_code = status_code
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
    user: AuthUser


class OtpProvider(Protocol):
    def create_code(self, channel: Channel) -> str: ...

    def deliver(self, channel: Channel, destination: str, code: str) -> None: ...


class DeterministicFakeOtpProvider:
    """Test/development provider. It deliberately retains no OTP values or logs."""

    codes = {Channel.PHONE: "111111", Channel.EMAIL: "222222"}

    def create_code(self, channel: Channel) -> str:
        return self.codes[channel]

    def deliver(self, channel: Channel, destination: str, code: str) -> None:
        if code != self.codes[channel]:
            raise AuthError("provider_error", 503)


class DisabledOtpProvider:
    """Fail closed until issue #7 supplies configured live SMS and email adapters."""

    def create_code(self, channel: Channel) -> str:
        return f"{secrets.randbelow(1_000_000):06d}"

    def deliver(self, channel: Channel, destination: str, code: str) -> None:
        raise AuthError("provider_unavailable", 503)


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


def _user(model: User) -> AuthUser:
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
        self, first_name: str, surname: str, phone: str, email: str, password: str
    ) -> AuthUser:
        email = email.strip().lower()
        phone = phone.strip()
        with self.sessions.begin() as session:
            existing = session.scalar(
                select(User.id).where((User.email == email) | (User.phone == phone))
            )
            if existing is not None:
                raise AuthError("account_exists", 409)
            user = User(
                first_name=first_name.strip(),
                surname=surname.strip(),
                phone=phone,
                email=email,
                password_hash=PASSWORD_HASHER.hash(password),
            )
            session.add(user)
            session.flush()
            self._send(session, user, Channel.PHONE)
            return _user(user)

    def verify(self, user_id: UUID, channel: Channel, code: str) -> AuthUser | SessionTokens:
        failure: AuthError | None = None
        result: AuthUser | SessionTokens | None = None
        with self.sessions.begin() as session:
            user = session.scalar(select(User).where(User.id == user_id).with_for_update())
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

    def resend(self, user_id: UUID, channel: Channel) -> None:
        with self.sessions.begin() as session:
            user = session.scalar(select(User).where(User.id == user_id).with_for_update())
            if user is None or (channel is Channel.EMAIL and not user.phone_verified):
                raise AuthError("invalid_verification", 400)
            if (channel is Channel.PHONE and user.phone_verified) or (
                channel is Channel.EMAIL and user.email_verified
            ):
                raise AuthError("invalid_verification", 400)
            self._send(session, user, channel)

    def login(self, identifier: str, password: str) -> SessionTokens:
        identifier = identifier.strip()
        with self.sessions.begin() as session:
            user = session.scalar(
                select(User).where((User.email == identifier.lower()) | (User.phone == identifier))
            )
            if (
                user is None
                or user.password_hash is None
                or not self._verify_password(user.password_hash, password)
            ):
                raise AuthError("invalid_credentials", 401)
            if not (user.phone_verified and user.email_verified):
                raise AuthError("invalid_credentials", 401)
            return self._new_session(session, user)

    def refresh(self, refresh_token: str) -> SessionTokens:
        with self.sessions.begin() as session:
            record = session.scalar(
                select(AuthSession).where(
                    AuthSession.refresh_token_hash == _hash_token(refresh_token),
                    AuthSession.revoked_at.is_(None),
                    AuthSession.expires_at > _now(),
                )
            )
            if record is None:
                raise AuthError("invalid_session", 401)
            user = session.get(User, record.user_id)
            if user is None or not (user.phone_verified and user.email_verified):
                raise AuthError("invalid_session", 401)
            record.revoked_at = _now()
            return self._new_session(session, user)

    def _send(self, session: Session, user: User, channel: Channel) -> None:
        recent = session.scalars(
            select(VerificationChallenge).where(
                VerificationChallenge.user_id == user.id,
                VerificationChallenge.channel == channel,
                VerificationChallenge.created_at > _now() - OTP_SEND_WINDOW,
            )
        ).all()
        if len(recent) >= MAX_OTP_SENDS:
            raise AuthError("otp_rate_limited", 429)
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
        self.provider.deliver(channel, user.phone if channel is Channel.PHONE else user.email, code)
        session.add(
            VerificationChallenge(
                user_id=user.id,
                channel=channel.value,
                code_hash=PASSWORD_HASHER.hash(code),
                expires_at=_now() + OTP_TTL,
            )
        )

    def _new_session(self, session: Session, user: User) -> SessionTokens:
        access, refresh = secrets.token_urlsafe(32), secrets.token_urlsafe(48)
        expires_at = _now() + SESSION_TTL
        session.add(
            AuthSession(
                user_id=user.id,
                access_token_hash=_hash_token(access),
                refresh_token_hash=_hash_token(refresh),
                expires_at=expires_at,
            )
        )
        return SessionTokens(access, refresh, expires_at, _user(user))

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
        self, first_name: str, surname: str, phone: str, email: str, password: str
    ) -> AuthUser:
        if any(u["email"] == email.lower() or u["phone"] == phone for u in self.users.values()):
            raise AuthError("account_exists", 409)
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

    def login(self, identifier: str, password: str) -> SessionTokens:
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
        expires_at = _now() + SESSION_TTL
        self.sessions[_hash_token(refresh)] = user_id
        return SessionTokens(access, refresh, expires_at, self._as_user(user_id))

    def resend(self, user_id: UUID, channel: Channel) -> None:
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
