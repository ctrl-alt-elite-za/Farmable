"""Reference imports and migration round trips in disposable PostgreSQL schemas."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from alembic import command
from farmable_backend.models import ReferenceImport, User
from farmable_backend.reference_imports import import_bundle
from sqlalchemy import inspect, select
from test_photo_sync_postgres import pg  # noqa: F401 -- disposable CI schema
from test_reference_imports import payload

pytestmark = pytest.mark.integration


@pytest.mark.parametrize("kind", ["market_prices", "crop_calendars", "crop_costs"])
def test_concurrent_reference_imports(request, kind):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0010")
    barrier = Barrier(4)

    def run(_):
        barrier.wait(timeout=10)
        return import_bundle(database.sessions, payload(kind))

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(run, range(4)))
    assert results.count(("imported", 1)) == 1
    assert results.count(("unchanged", 1)) == 3
    with database.sessions() as session:
        assert len(list(session.scalars(select(ReferenceImport)))) == 1


def test_reference_migration_round_trip_preserves_users(request):
    database = request.getfixturevalue("pg")
    with database.sessions() as session:
        before = set(session.scalars(select(User.id)))
    command.upgrade(database.config, "0010")
    for kind in ("market_prices", "crop_calendars", "crop_costs"):
        assert import_bundle(database.sessions, payload(kind)) == ("imported", 1)
    command.downgrade(database.config, "0009")
    tables = inspect(database.engine).get_table_names(schema=database.schema)
    assert not any(table.startswith("reference_") for table in tables)
    with database.sessions() as session:
        assert set(session.scalars(select(User.id))) == before
    command.upgrade(database.config, "0010")
    assert import_bundle(database.sessions, payload()) == ("imported", 1)
