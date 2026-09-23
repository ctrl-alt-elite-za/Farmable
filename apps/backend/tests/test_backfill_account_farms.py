"""Backfill of the one-farm-per-account invariant for pre-#9 accounts."""

from datetime import UTC, datetime

import pytest
from farmable_backend.auth import DEFAULT_FARM_NAME
from farmable_backend.backfill_account_farms import backfill_account_farms
from farmable_backend.models import AuthIdentity, Base, Farm, User
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

PASSWORD_HASH = "$argon2id$v=19$m=65536,t=3,p=4$placeholder"  # noqa: S105 - synthetic


@pytest.fixture
def sessions():
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    yield sessionmaker(engine, expire_on_commit=False)
    engine.dispose()


def _identity(session, index, *, with_identity=True):
    owner = User()
    session.add(owner)
    session.flush()
    if with_identity:
        session.add(
            AuthIdentity(
                id=owner.id,
                first_name="Sipho",
                surname="Dlamini",
                phone=f"+2712345{index:04d}",
                email=f"owner-{index}@example.com",
                password_hash=PASSWORD_HASH,
                phone_verified=True,
                email_verified=True,
            )
        )
        session.flush()
    return owner.id


def _farms(session, owner):
    return session.scalars(select(Farm).where(Farm.owner_id == owner)).all()


def test_backfill_creates_one_default_farm_for_an_identity_without_one(sessions):
    with sessions.begin() as session:
        owner = _identity(session, 0)
    with sessions.begin() as session:
        assert backfill_account_farms(session) == 1
    with sessions() as session:
        farms = _farms(session, owner)
        assert len(farms) == 1
        assert farms[0].name == DEFAULT_FARM_NAME
        assert farms[0].deleted_at is None


def test_backfill_is_idempotent_across_runs(sessions):
    with sessions.begin() as session:
        owner = _identity(session, 0)
    with sessions.begin() as session:
        assert backfill_account_farms(session) == 1
    with sessions.begin() as session:
        assert backfill_account_farms(session) == 0
    with sessions() as session:
        assert len(_farms(session, owner)) == 1


def test_backfill_leaves_an_owner_that_already_has_a_farm_untouched(sessions):
    with sessions.begin() as session:
        owner = _identity(session, 0)
        session.add(Farm(owner_id=owner, name="Existing farm"))
    with sessions() as session:
        before = _farms(session, owner)[0]
        existing_id, existing_name = before.id, before.name
    with sessions.begin() as session:
        assert backfill_account_farms(session) == 0
    with sessions() as session:
        farms = _farms(session, owner)
        assert len(farms) == 1
        assert (farms[0].id, farms[0].name) == (existing_id, existing_name)


def test_backfill_skips_deleted_accounts_whose_farm_is_tombstoned(sessions):
    # delete_account keeps the users row and soft-deletes the farm, but removes
    # the auth_identities row. Enumerating users would resurrect a live farm for
    # every deleted account; enumerating identities must not.
    with sessions.begin() as session:
        owner = _identity(session, 0, with_identity=False)
        session.add(Farm(owner_id=owner, name="Gone", deleted_at=datetime.now(UTC)))
    with sessions.begin() as session:
        assert backfill_account_farms(session) == 0
    with sessions() as session:
        farms = _farms(session, owner)
        assert len(farms) == 1
        assert farms[0].deleted_at is not None


def test_backfill_handles_a_mixed_population_in_one_run(sessions):
    with sessions.begin() as session:
        bare = [_identity(session, index) for index in (0, 1)]
        settled = _identity(session, 2)
        session.add(Farm(owner_id=settled, name="Existing farm"))
    with sessions.begin() as session:
        assert backfill_account_farms(session) == 2
    with sessions() as session:
        total = session.scalar(select(func.count()).select_from(Farm))
        assert total == 3
        for owner in bare:
            assert [farm.name for farm in _farms(session, owner)] == [DEFAULT_FARM_NAME]
