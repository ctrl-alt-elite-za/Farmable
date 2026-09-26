"""Weather arithmetic, real HTTP save/queue path and durable failure recovery."""

import asyncio
import io
from contextlib import asynccontextmanager
from datetime import date, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from uuid import uuid4

import httpx
import pytest
from alembic import command
from alembic.config import Config
from farmable_backend import worker as worker_entry
from farmable_backend.demo_seed import seed_demo_farm
from farmable_backend.forecasts import import_bundle
from farmable_backend.integrations.open_meteo import OpenMeteo
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.models import ForecastState, Section, WeatherJob, WeatherRiskClimatology
from farmable_backend.record_access import db_now
from farmable_backend.weather_jobs import WeatherJobs, enqueue_weather
from farmable_backend.weather_policy import (
    POLICY_HASH,
    calculate,
    grid_cell,
    parse_daily,
    planting_years,
    request_period,
)
from farmable_backend.weather_worker import WeatherWorker
from sqlalchemy import func, select
from test_farm_schema import _index_statements, _orm_sql, _table_elements
from test_forecasts import bundle, get_outlook, raw

pytest_plugins = ("test_records_api",)
POINT = {"type": "Point", "coordinates": [28.1234567, -25.456789]}


def history(first=2010, last=2024):
    start, end = request_period(first, last)
    return {start + timedelta(days=i): (5, 25, 2) for i in range((end - start).days + 1)}


def config(**kwargs):
    return ServiceSettings(environment="ci", integrations_mode="fake", **kwargs)


def save_location(records, boundary=POINT, version=1):
    return records.client.put(
        f"/farms/{records.ids.farm}/sections/{records.ids.section}",
        json={
            "mutation_id": str(uuid4()),
            "expected_version": version,
            "name": "Weather test section",
            "boundary": boundary,
        },
    )


def queue(records):
    response = save_location(records)
    assert response.status_code == 200, response.text
    with records.sessions() as session:
        return session.scalar(select(WeatherJob))


def enable_outlook(records):
    records.app.state.forecast_data_mode = "sample"
    records.app.state.services.open_meteo.settings.integrations_mode = "fake"
    with records.sessions.begin() as session:
        session.add(ForecastState(id=1))
    import_bundle(records.sessions, "sample-v1", raw(bundle()), "sample")


@pytest.mark.parametrize(
    "point,cell",
    [
        (POINT, (-255, 281)),
        ({"type": "Point", "coordinates": [28.15, -25.45]}, (-255, 282)),
        ({"type": "Point", "coordinates": [180, 90]}, (900, -1800)),
        (
            {
                "type": "Polygon",
                "coordinates": [[[28.1, -25.4], [28.2, -25.4], [28.2, -25.5], [28.1, -25.4]]],
            },
            (-255, 282),
        ),
    ],
)
def test_round_only_valid_location(point, cell):
    assert grid_cell(point) == cell


@pytest.mark.parametrize(
    "boundary",
    [
        None,
        {},
        {"type": "Point", "coordinates": [True, 0]},
        {"type": "Point", "coordinates": [181, 0]},
        {"type": "Point", "coordinates": [0, float("nan")]},
        {"type": "Polygon", "coordinates": []},
        {"type": "Polygon", "coordinates": [[[179, 0], [-179, 0], [179, 1], [179, 0]]]},
    ],
)
def test_invalid_location_is_not_sent(boundary):
    assert grid_cell(boundary) is None


def test_complete_years_include_cross_year_growing_windows():
    assert planting_years(date(2026, 1, 1)) == (2010, 2024)
    assert planting_years(date(2026, 12, 31)) == (2011, 2025)
    assert planting_years(date(2026, 8, 3)) == (2010, 2024)
    assert planting_years(date(2026, 8, 4)) == (2011, 2025)
    assert request_period(2010, 2024)[1] == date(2025, 7, 28)


def test_event_shares_use_years_not_days_and_include_leap_and_cross_year_days():
    daily = history()
    daily[date(2012, 2, 29)] = (-1, 35, 2)
    # This is inside the final December-2024 cabbage window, not a 16th planting year.
    for n in range(7):
        daily[date(2025, 1, 1) + timedelta(days=n)] = (5, 25, 0.9)
    rows = calculate(daily, 2010, 2024)
    assert len(rows) == 96
    feb = rows["cabbage", 2]
    assert feb["event_years"] == {"frost": 1, "heat_stress": 1, "dry_spell": 0}
    assert feb["shares"]["frost"] == 1 / 15
    december = rows["cabbage", 12]
    assert december["event_years"]["dry_spell"] == 1
    assert december["years_observed"] == 15


def test_threshold_boundaries_and_dry_runs_do_not_bleed_between_years():
    daily = history()
    for year in range(2010, 2025):
        daily[date(year, 1, 1)] = (0, 34.9, 1)
        for n in range(6):
            daily[date(year, 1, 2) + timedelta(days=n)] = (0, 34.9, 0)
    assert calculate(daily, 2010, 2024)["cabbage", 1]["shares"] == {
        "frost": 0,
        "heat_stress": 0,
        "dry_spell": 0,
    }
    del daily[date(2012, 2, 29)]
    with pytest.raises(ValueError, match="coverage"):
        calculate(daily, 2010, 2024)


@pytest.mark.parametrize(
    "change", ["null", "nan", "wrong_units", "duplicate", "missing", "inverted"]
)
def test_daily_payload_validation(change):
    payload = {
        "daily_units": {
            "temperature_2m_min": "°C",
            "temperature_2m_max": "°C",
            "precipitation_sum": "mm",
        },
        "daily": {
            "time": ["2020-01-01", "2020-01-02"],
            "temperature_2m_min": [1, 2],
            "temperature_2m_max": [3, 4],
            "precipitation_sum": [2, 2],
        },
    }
    if change in {"null", "nan"}:
        payload["daily"]["precipitation_sum"][0] = None if change == "null" else float("nan")
    elif change == "wrong_units":
        payload["daily_units"]["precipitation_sum"] = "inch"
    elif change == "duplicate":
        payload["daily"]["time"][1] = "2020-01-01"
    elif change == "missing":
        payload["daily"]["time"].pop()
    else:
        payload["daily"]["temperature_2m_min"][0] = 9
    with pytest.raises(ValueError):
        parse_daily(payload, date(2020, 1, 1), date(2020, 1, 2))


def test_weather_risk_computed_on_section_location(records):
    job = queue(records)
    assert job.latitude_tenths == -255 and job.longitude_tenths == 281
    enable_outlook(records)

    async def run():
        registry = ServiceRegistry(config())
        try:
            worker = WeatherWorker(records.sessions, registry.open_meteo)
            assert await worker.once()
            assert not await worker.once()
            assert registry.transport.calls["open_meteo"] == 1
        finally:
            await registry.close()

    asyncio.run(run())
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherRiskClimatology)) == 96
    weather = get_outlook(records).json()["weather_risk"]
    assert weather["status"] == "available"
    assert weather["data_kind"] == "synthetic"
    assert weather["source"] == "synthetic fixture"
    assert weather["shares"] == {"frost": 0, "heat_stress": 0, "dry_spell": 0}
    assert weather["policy_sha256"] == POLICY_HASH
    assert weather["years_observed"] == 15
    # A live API must not serve cached fixtures as real weather.
    records.app.state.services.open_meteo.settings.integrations_mode = "live"
    assert get_outlook(records).json()["weather_risk"]["status"] == "unavailable"


def test_shared_grid_reuses_work_and_location_change_does_not_reuse_old_risk(records):
    queued = queue(records)
    jobs = WeatherJobs(records.sessions, "synthetic")
    claimed = jobs.claim()
    rows = calculate(
        history(claimed.first_year, claimed.last_year), claimed.first_year, claimed.last_year
    )
    assert jobs.finish(claimed, rows, "a" * 64)
    with records.sessions.begin() as session:
        assert (
            enqueue_weather(session, {"type": "Point", "coordinates": [28.12, -25.46]}) == queued.id
        )
    assert jobs.claim() is None
    enable_outlook(records)
    assert get_outlook(records).json()["weather_risk"]["status"] == "available"
    assert save_location(records, {"type": "Point", "coordinates": [30, -26]}, 2).status_code == 200
    assert get_outlook(records).json()["weather_risk"]["status"] == "unavailable"
    assert save_location(records, None, 3).status_code == 200
    assert get_outlook(records).json()["weather_risk"]["status"] == "unavailable"


def test_failed_job_retries_later_and_outlook_keeps_prices(records):
    queued = queue(records)
    enable_outlook(records)

    async def run():
        registry = ServiceRegistry(config(fault_open_meteo=True))
        try:
            worker = WeatherWorker(records.sessions, registry.open_meteo)
            assert await worker.once()
            assert not await worker.once()
            assert registry.transport.calls["open_meteo"] == 0
            with records.sessions.begin() as session:
                job = session.get(WeatherJob, queued.id)
                assert job.status == "pending" and job.error_code == "weather_unavailable"
                job.next_attempt_at = db_now(session) - timedelta(seconds=1)
            registry.open_meteo.settings.fault_open_meteo = False
            assert await worker.once()
        finally:
            await registry.close()

    before = get_outlook(records).json()
    asyncio.run(run())
    after = get_outlook(records).json()
    assert before["weather_risk"]["status"] == "unavailable"
    assert before["price_range"] == after["price_range"]
    assert after["weather_risk"]["status"] == "available"


def test_expired_worker_cannot_overwrite_successor(records):
    queued = queue(records)
    jobs = WeatherJobs(records.sessions, "historical")
    old = jobs.claim()
    assert jobs.claim() is None
    with records.sessions.begin() as session:
        session.get(WeatherJob, queued.id).lease_expires_at = db_now(session) - timedelta(seconds=1)
    new = jobs.claim()
    rows = calculate(history(new.first_year, new.last_year), new.first_year, new.last_year)
    assert not jobs.finish(old, rows, "a" * 64)
    assert not jobs.fail(old)
    assert jobs.finish(new, rows, "b" * 64)
    with records.sessions() as session:
        row = session.get(WeatherRiskClimatology, (queued.id, "cabbage", 1))
        assert row.payload["source_sha256"] == "b" * 64


def test_queue_is_transactional_and_demo_seed_queues_once(records):
    with records.sessions() as session:
        # Mirror the API's flushed section write. SQLite's legacy driver does
        # not begin a physical transaction for SELECT-only work before SAVEPOINT;
        # a separate PostgreSQL test covers standalone outbox rollback as well.
        section = session.get(Section, records.ids.section)
        original_name = section.name
        section.name = "Rollback weather save"
        session.flush()
        enqueue_weather(session, POINT)
        session.rollback()
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherJob)) == 0
        assert session.get(Section, records.ids.section).name == original_name
    with records.sessions.begin() as session:
        seed_demo_farm(session)
        seed_demo_farm(session)
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherJob)) == 1


def test_no_location_does_not_enqueue_and_cross_farm_cannot_trigger(records):
    assert save_location(records, {}).status_code == 200
    response = records.client.put(
        f"/farms/{records.ids.farm}/sections/{uuid4()}",
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 1,
            "name": "Other",
            "boundary": POINT,
        },
    )
    assert response.status_code == 404
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherJob)) == 0


def test_provider_only_sends_grid_with_bounded_retries():
    requests, delays = [], []

    def response(request):
        requests.append(request)
        return httpx.Response(503, json={"error": True})

    async def sleep(delay):
        delays.append(delay)

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(response)) as client:
            provider = OpenMeteo("open_meteo", client, config(), sleep=sleep, jitter=lambda: 0)
            result = await provider.history(-255, 281, date(2010, 1, 1), date(2025, 7, 28))
            assert not result.ok
            assert provider.timeout == 10
            assert (
                await provider.history(-25.5, 28.1, date(2020, 1, 1), date(2020, 1, 2))
            ).error == "invalid_input"

    asyncio.run(run())
    assert len(requests) == 3 and delays == [0.5, 1.0]
    params = requests[0].url.params
    assert params["latitude"] == "-25.5" and params["longitude"] == "28.1"
    assert set(params) == {
        "latitude",
        "longitude",
        "start_date",
        "end_date",
        "daily",
        "temperature_unit",
        "precipitation_unit",
        "timezone",
        "models",
    }


def test_weather_migration_matches_orm():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0007:0008", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql and "DROP TABLE" not in sql
    for table in ("weather_jobs", "weather_risk_climatology"):
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)
        assert _index_statements(sql, table) == _index_statements(_orm_sql(table), table)


def test_section_create_and_replay_enqueue_once(records):
    body = {"id": str(uuid4()), "mutation_id": str(uuid4()), "name": "New field", "boundary": POINT}
    url = f"/farms/{records.ids.farm}/sections"
    assert records.client.post(url, json=body).status_code == 200
    assert records.client.post(url, json=body).status_code == 200
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherJob)) == 1


def test_backfill_picks_existing_locations_without_changing_sections(records):
    with records.sessions.begin() as session:
        section = session.get(Section, records.ids.section)
        section.boundary = POINT
        old_version = section.version
    jobs = WeatherJobs(records.sessions, "synthetic")
    assert jobs.enqueue_existing() is None
    assert jobs.enqueue_existing() is None
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(WeatherJob)) == 1
        assert session.get(Section, records.ids.section).version == old_version


def test_partial_provider_data_cannot_publish_zero_or_partial_risks(records):
    queued = queue(records)

    async def run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(200, json={"daily": {"time": []}})
            )
        ) as client:
            worker = WeatherWorker(records.sessions, OpenMeteo("open_meteo", client, config()))
            assert await worker.once()

    asyncio.run(run())
    with records.sessions() as session:
        assert session.get(WeatherJob, queued.id).status == "pending"
        assert session.scalar(select(func.count()).select_from(WeatherRiskClimatology)) == 0


def test_weather_provider_breaker_and_timeout_are_effective():
    calls = []

    async def response(request):
        calls.append(request)
        await asyncio.sleep(0.1)
        return httpx.Response(200, json={})

    async def no_sleep(delay):
        pass

    async def run():
        async with httpx.AsyncClient(transport=httpx.MockTransport(response)) as client:
            provider = OpenMeteo("open_meteo", client, config(), timeout=0.001, sleep=no_sleep)
            for _ in range(5):
                result = await provider.history(-254, 283, date(2020, 1, 1), date(2020, 1, 2))
                assert result.error == "timeout"
            assert provider.opened_at is not None
            assert (
                await provider.history(-254, 283, date(2020, 1, 1), date(2020, 1, 2))
            ).error == "unavailable"

    asyncio.run(run())
    assert len(calls) == 15


@pytest.mark.parametrize("queue_fails", [False, True])
def test_weather_worker_starts_without_photo_bucket_and_closes_resources(monkeypatch, queue_fails):
    @asynccontextmanager
    async def opened():
        yield

    async def queue_run(**kwargs):
        await asyncio.sleep(0)
        if queue_fails:
            raise RuntimeError("queue")

    weather = SimpleNamespace(stop=asyncio.Event())
    weather.run = AsyncMock(side_effect=weather.stop.wait)
    services = SimpleNamespace(open_meteo=Mock(), close=AsyncMock())
    database = Mock()
    monkeypatch.setattr(worker_entry, "ServiceSettings", config)
    monkeypatch.setattr(
        worker_entry, "Settings", lambda: SimpleNamespace(photo_bucket=None, log_level="info")
    )
    monkeypatch.setattr(worker_entry, "configure_logging", Mock())
    monkeypatch.setattr(
        worker_entry,
        "create_task_app",
        lambda _: SimpleNamespace(open_async=opened, run_worker_async=queue_run),
    )
    monkeypatch.setattr(worker_entry, "Database", lambda _: database)
    monkeypatch.setattr(worker_entry, "ServiceRegistry", lambda _: services)
    monkeypatch.setattr(worker_entry, "WeatherWorker", lambda *args: weather)
    retention = SimpleNamespace(stop=asyncio.Event())
    retention.run = AsyncMock(side_effect=retention.stop.wait)
    monkeypatch.setattr(worker_entry, "RetentionWorker", lambda _: retention)
    photo = SimpleNamespace(stop=asyncio.Event())

    async def run_photo(**kwargs):
        await photo.stop.wait()

    photo.run = AsyncMock(side_effect=run_photo)
    photo_factory = Mock(return_value=photo)
    monkeypatch.setattr(worker_entry, "PhotoWorker", photo_factory)
    if queue_fails:
        with pytest.raises(RuntimeError, match="queue"):
            asyncio.run(worker_entry.run())
    else:
        asyncio.run(worker_entry.run())
    assert weather.stop.is_set()
    assert retention.stop.is_set()
    retention.run.assert_awaited_once()
    weather.run.assert_awaited_once()
    services.close.assert_awaited_once()
    database.close.assert_called_once()
    assert photo.stop.is_set()
    photo.run.assert_awaited_once_with(cleanup_only=True)
