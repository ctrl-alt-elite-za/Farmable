"""PostgreSQL coverage for account ownership scope, revocation and deletion."""

import json
from uuid import uuid4

import pytest
from farmable_backend.account import AccountService
from farmable_backend.account_schemas import FarmUpdate, ProfileUpdate
from farmable_backend.auth import AuthService, Channel, DeterministicFakeOtpProvider, SessionTokens
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.models import AccountProfile, AuthIdentity, AuthSession, Farm, User
from farmable_backend.record_access import ApiError
from sqlalchemy import func, select
from sqlalchemy.orm import Session, sessionmaker

pytestmark = pytest.mark.integration

PASSWORD = "correct horse battery staple"  # noqa: S105 - synthetic test credential


@pytest.fixture
def engine():
    value = make_engine(Settings())
    yield value
    value.dispose()


def _register(service, suffix, index):
    digits = (int(suffix[:9], 16) + index) % 1_000_000_000
    tokens = service.signup(
        "Sipho",
        "Dlamini",
        f"+278{digits:09d}",
        f"account-{suffix}-{index}@example.com",
        PASSWORD,
    )
    service.verify(tokens.id, Channel.PHONE, "111111")
    session = service.verify(tokens.id, Channel.EMAIL, "222222")
    assert isinstance(session, SessionTokens)
    return session


def _cleanup(engine, owners):
    with Session(engine) as session:
        for owner in session.scalars(select(User).where(User.id.in_(owners))):
            session.delete(owner)
        session.commit()


def test_account_deletion_is_scoped_to_the_confirming_owner(engine):
    suffix = uuid4().hex
    sessions = sessionmaker(engine, expire_on_commit=False)
    auth = AuthService(sessions, DeterministicFakeOtpProvider())
    account = AccountService(sessions)
    first = _register(auth, suffix, 0)
    second = _register(auth, suffix, 1)
    owners = [first.user.id, second.user.id]
    try:
        account.update_profile(
            f"Bearer {first.access_token}", ProfileUpdate(preferred_language="zu")
        )
        account.update_farm(f"Bearer {second.access_token}", FarmUpdate(name="Second farm"))
        with pytest.raises(ApiError) as rejected:
            account.delete_account(f"Bearer {first.access_token}", "wrong password")
        assert rejected.value.status == 401
        account.delete_account(f"Bearer {first.access_token}", PASSWORD)
        with Session(engine) as session:
            assert session.get(AuthIdentity, first.user.id) is None
            assert session.get(User, first.user.id) is not None
            assert session.get(AccountProfile, first.user.id) is None
            remaining = session.scalar(
                select(func.count())
                .select_from(AuthSession)
                .where(AuthSession.user_id == first.user.id)
            )
            assert remaining == 0
            farm = session.scalar(select(Farm).where(Farm.owner_id == first.user.id))
            assert farm is not None and farm.deleted_at is not None
        with pytest.raises(ApiError) as blocked:
            account.profile(f"Bearer {first.access_token}")
        assert blocked.value.status == 401
        survivor = account.farm(f"Bearer {second.access_token}")
        assert survivor.name == "Second farm"
        assert survivor.owner_id == second.user.id
    finally:
        _cleanup(engine, owners)


def test_export_and_revoke_all_stay_owner_scoped(engine):
    suffix = uuid4().hex
    sessions = sessionmaker(engine, expire_on_commit=False)
    auth = AuthService(sessions, DeterministicFakeOtpProvider())
    account = AccountService(sessions)
    first = _register(auth, suffix, 0)
    second = _register(auth, suffix, 1)
    owners = [first.user.id, second.user.id]
    try:
        document = account.export_document(f"Bearer {first.access_token}")
        body = json.dumps(document)
        assert document["account"]["id"] == str(first.user.id)
        assert [farm["owner_id"] for farm in document["farms"]] == [str(first.user.id)]
        assert str(second.user.id) not in body
        for field in ("password_hash", "code_hash", "access_token_hash", "refresh_token_hash"):
            assert field not in body
        extra = auth.login(document["account"]["email"], PASSWORD)
        account.revoke_all(f"Bearer {first.access_token}")
        for tokens in (first, extra):
            with pytest.raises(ApiError):
                account.profile(f"Bearer {tokens.access_token}")
        assert account.profile(f"Bearer {second.access_token}").id == second.user.id
    finally:
        _cleanup(engine, owners)
