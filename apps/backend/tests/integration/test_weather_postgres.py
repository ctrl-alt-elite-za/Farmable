"""Weather outbox and lease races on disposable PostgreSQL, not SQLite emulation."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from alembic import command
from farmable_backend.models import AuthIdentity, WeatherJob, WeatherRiskClimatology
from farmable_backend.weather_jobs import WeatherJobs, enqueue_weather
from farmable_backend.weather_policy import calculate
from sqlalchemy import func, inspect, select
from test_photo_sync_postgres import pg  # noqa: F401 -- isolated schema fixture
from test_weather import POINT, history

pytestmark = pytest.mark.integration


def test_weather_concurrent_grid_enqueue_and_claim(request):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0008")
    barrier = Barrier(4)

    def enqueue(_):
        with database.sessions.begin() as session:
            barrier.wait(timeout=10)
            return enqueue_weather(session, POINT)

    with ThreadPoolExecutor(max_workers=4) as pool:
        keys = list(pool.map(enqueue, range(4)))
    assert len(set(keys)) == 1
    with database.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherJob)) == 1
    jobs = WeatherJobs(database.sessions, "historical")

    def claim(_):
        barrier.wait(timeout=10)
        return jobs.claim()

    with ThreadPoolExecutor(max_workers=4) as pool:
        claims = list(pool.map(claim, range(4)))
    owned = [claim for claim in claims if claim is not None]
    assert len(owned) == 1
    job = owned[0]
    rows = calculate(history(job.first_year, job.last_year), job.first_year, job.last_year)
    assert jobs.finish(job, rows, "a" * 64)
    with database.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherRiskClimatology)) == 96


def test_weather_standalone_outbox_rollback_and_migration_roundtrip(request):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0008")
    with database.sessions() as session:
        enqueue_weather(session, POINT)
        session.rollback()
    with database.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherJob)) == 0
        assert session.get(AuthIdentity, database.ids.owner).phone_verified
    command.downgrade(database.config, "0007")
    tables = inspect(database.engine).get_table_names(schema=database.schema)
    assert "weather_jobs" not in tables and "weather_risk_climatology" not in tables
    command.upgrade(database.config, "0008")
    with database.sessions.begin() as session:
        assert enqueue_weather(session, POINT)
