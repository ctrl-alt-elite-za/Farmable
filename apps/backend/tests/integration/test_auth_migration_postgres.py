"""Upgrade/rollback probes own a random schema inside the disposable CI database."""

import os
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from farmable_backend import database
from farmable_backend.config import Settings
from farmable_backend.models import AuthIdentity, Farm, User
from sqlalchemy import create_engine, func, inspect, select, update
from sqlalchemy.exc import OperationalError
from sqlalchemy.orm import Session
from sqlalchemy.schema import CreateSchema, DropSchema

pytestmark = pytest.mark.integration


@pytest.fixture
def migration_schema(monkeypatch):
    assert os.environ.get("ENVIRONMENT") == "ci", "Use the disposable integration harness"
    schema = "auth_migration_" + uuid4().hex
    admin = database.make_engine(Settings())
    engine = create_engine(
        Settings().database_url.get_secret_value(),
        connect_args={
            "connect_timeout": 5,
            "options": (
                f"-c statement_timeout=5000 -c lock_timeout=1000 -c search_path={schema},public"
            ),
        },
        hide_parameters=True,
    )

    def migration_engine(settings, *, migration=False):
        assert migration, "Alembic must request migration lock-timeout settings"
        return engine

    try:
        with admin.begin() as connection:
            connection.execute(CreateSchema(schema))
        monkeypatch.setattr(database, "make_engine", migration_engine)
        # The public CI schema already has an Alembic version table. Explicitly
        # scope ours so it cannot be mistaken for that schema's current revision.
        config = Config("alembic.ini")
        config.attributes["version_table_schema"] = schema
        command.upgrade(config, "0003")
        yield engine, config, schema
    finally:
        engine.dispose()
        with admin.begin() as connection:
            connection.execute(DropSchema(schema, cascade=True, if_exists=True))
        admin.dispose()


def seed_existing_farm(engine):
    with Session(engine, expire_on_commit=False) as session:
        owner = User()
        session.add(owner)
        session.flush()
        farm = Farm(owner_id=owner.id, name="Existing production farm")
        session.add(farm)
        session.commit()
        return owner.id, farm.id


def snapshot(engine):
    with engine.connect() as connection:
        return (
            connection.execute(select(User.__table__)).all(),
            connection.execute(select(Farm.__table__)).all(),
        )


def test_auth_migration_preserves_existing_ownership_and_can_rollback(migration_schema):
    engine, config, schema = migration_schema
    seed_existing_farm(engine)
    before = snapshot(engine)
    command.upgrade(config, "0004")
    assert snapshot(engine) == before
    assert {column["name"] for column in inspect(engine).get_columns("users", schema=schema)} == {
        "id",
        "created_at",
        "updated_at",
    }
    with Session(engine) as session:
        assert session.scalar(select(func.count()).select_from(AuthIdentity)) == 0
        assert session.scalar(select(func.current_setting("lock_timeout"))) == "1s"
        assert session.scalar(select(func.current_setting("statement_timeout"))) == "5s"
    command.downgrade(config, "0003")
    assert "auth_identities" not in inspect(engine).get_table_names(schema=schema)
    assert snapshot(engine) == before
    command.upgrade(config, "0004")
    assert snapshot(engine) == before


def test_auth_migration_lock_timeout_rolls_back_then_explicit_retry_succeeds(migration_schema):
    engine, config, schema = migration_schema
    owner_id, _farm_id = seed_existing_farm(engine)
    before = snapshot(engine)
    # An uncommitted writer holds RowExclusiveLock on users. Creating the FK
    # must time out rather than wait indefinitely; no handwritten LOCK SQL.
    with engine.connect() as blocker:
        transaction = blocker.begin()
        blocker.execute(update(User).where(User.id == owner_id).values(updated_at=func.now()))
        try:
            with pytest.raises(OperationalError) as failure:
                command.upgrade(config, "0004")
            assert getattr(failure.value.orig, "sqlstate", None) == "55P03"
        finally:
            transaction.rollback()
    with engine.connect() as connection:
        context = MigrationContext.configure(connection, opts={"version_table_schema": schema})
        assert context.get_current_revision() == "0003"
    assert "auth_identities" not in inspect(engine).get_table_names(schema=schema)
    assert snapshot(engine) == before
    # This is a deliberately tested recovery action, not a retry of a failed test.
    command.upgrade(config, "0004")
    assert "auth_identities" in inspect(engine).get_table_names(schema=schema)
    assert snapshot(engine) == before
