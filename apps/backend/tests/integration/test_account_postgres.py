"""PostgreSQL coverage for account ownership scope, revocation and deletion."""

import json
from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest
from farmable_backend.account import AccountService
from farmable_backend.account_schemas import FarmUpdate, ProfileUpdate
from farmable_backend.auth import AuthService, Channel, DeterministicFakeOtpProvider, SessionTokens
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.models import AccountProfile, AuthIdentity, AuthSession, Farm, User
from farmable_backend.record_access import ApiError
from sqlalchemy import event, func, select
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
        ip=f"198.51.100.{(int(suffix[:2], 16) % 250) + 1}",
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
    account = AccountService(sessions, export_token_secret="integration-export-token-secret")
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


def test_concurrent_first_language_writes_insert_exactly_one_profile(engine):
    """The real race behind AccountService._set_language's owner-row lock.

    account_profiles is a get-or-insert keyed on the owner. Without the
    `.with_for_update()` SELECT on the users row, two concurrent first-time
    language writes both read AccountProfile as None, both INSERT, and the
    second violates the account_profiles primary key -- an unhandled
    IntegrityError surfacing to the caller as a 500.

    Only real PostgreSQL can show this: SQLite emits no FOR UPDATE clause, so
    the SQLite sibling test can only assert statement ordering and stays green
    if the lock is deleted. Here the second thread blocks on the owner row,
    and once the first commits it takes a fresh READ COMMITTED snapshot, sees
    the committed profile row, and takes the UPDATE branch instead.

    A barrier placed before `sessions.begin()` does NOT reliably force this:
    each transaction runs an unrelated authenticate()/get() preamble first,
    and the two threads' connection-pool checkouts are asymmetric (one reuses
    a warm connection, the other may open a fresh one), so the thread that
    reaches the contended SELECT first can commit and release before the
    second thread ever arrives -- the race the test exists to force may
    simply not happen, and the test passes for the wrong reason regardless of
    whether the lock is present. Instead, an engine-level `before_cursor_execute`
    hook holds each thread immediately before it executes the owner-row lock
    statement itself, so both threads issue that exact statement at
    effectively the same instant and PostgreSQL's row lock is what serializes
    them -- the failure mode under test is forced to occur, not hoped for.

    The winner is genuinely nondeterministic, so only the row count and the
    set of admissible values are asserted.
    """
    suffix = uuid4().hex
    sessions = sessionmaker(engine, expire_on_commit=False)
    auth = AuthService(sessions, DeterministicFakeOtpProvider())
    account = AccountService(sessions, export_token_secret="integration-export-token-secret")
    tokens = _register(auth, suffix, 0)
    owners = [tokens.user.id]
    languages = ("zu", "xh")
    lock_barrier = Barrier(len(languages), timeout=10)

    def synchronize_on_owner_lock(conn, cursor, statement, parameters, context, executemany):  # noqa: PLR0913
        if statement.startswith("SELECT users.id"):
            lock_barrier.wait()

    def write(language):
        try:
            return account.update_profile(
                f"Bearer {tokens.access_token}", ProfileUpdate(preferred_language=language)
            ).preferred_language
        except Exception as error:  # noqa: BLE001 - the failure mode under test
            return error

    event.listen(engine, "before_cursor_execute", synchronize_on_owner_lock)
    try:
        with ThreadPoolExecutor(max_workers=len(languages)) as executor:
            results = list(executor.map(write, languages))
        assert [item for item in results if isinstance(item, Exception)] == []
        assert set(results) <= set(languages)
        with Session(engine) as session:
            profiles = session.scalars(
                select(AccountProfile).where(AccountProfile.user_id == tokens.user.id)
            ).all()
            assert len(profiles) == 1
            assert profiles[0].preferred_language in languages
    finally:
        event.remove(engine, "before_cursor_execute", synchronize_on_owner_lock)
        _cleanup(engine, owners)


def test_export_and_revoke_all_stay_owner_scoped(engine):
    suffix = uuid4().hex
    sessions = sessionmaker(engine, expire_on_commit=False)
    auth = AuthService(sessions, DeterministicFakeOtpProvider())
    account = AccountService(sessions, export_token_secret="integration-export-token-secret")
    first = _register(auth, suffix, 0)
    second = _register(auth, suffix, 1)
    owners = [first.user.id, second.user.id]
    try:
        account.set_consent(f"Bearer {first.access_token}", "data_export", "1", True)
        account.set_consent(f"Bearer {second.access_token}", "data_export", "1", True)
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
