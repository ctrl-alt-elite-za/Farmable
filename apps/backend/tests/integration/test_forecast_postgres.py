"""Activation/idempotency races use real row locks in an isolated CI schema."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import httpx
import pytest
from alembic import command
from farmable_backend.forecast_notifications import GitHubFailureNotifier
from farmable_backend.forecasts import activate, import_bundle, outlook
from farmable_backend.models import AuthIdentity, ForecastRun, ForecastState
from sqlalchemy import inspect, select
from test_forecast_notifications import FAILURE, FakeGitHub, config
from test_forecasts import bundle, raw
from test_photo_sync_postgres import pg  # noqa: F401 -- isolated schema fixture

pytestmark = pytest.mark.integration


def test_concurrent_failure_notifications_create_one_issue(request):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0007")
    github = FakeGitHub()
    barrier = Barrier(4)
    notifier = GitHubFailureNotifier(
        database.sessions, config(), transport=httpx.MockTransport(github)
    )

    def notify(_):
        barrier.wait(timeout=10)
        notifier(FAILURE)

    with ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(notify, range(4)))
    assert len(github.issues) == 1


@pytest.mark.parametrize("same_id", [False, True])
def test_concurrent_imports_have_exactly_one_active_snapshot(request, same_id):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0007")
    barrier = Barrier(4)

    def run(index):
        name = "same" if same_id else f"run-{index}"
        data = raw(bundle(name))
        barrier.wait(timeout=10)
        return import_bundle(database.sessions, name, data, "sample")

    with ThreadPoolExecutor(max_workers=4) as pool:
        results = list(pool.map(run, range(4)))
    assert all(result.status == "active" for result in results)
    with database.sessions() as session:
        runs = list(session.scalars(select(ForecastRun)))
        assert len(runs) == (1 if same_id else 4)
        active = [run for run in runs if run.status == "active"]
        assert len(active) == 1
        assert session.get(ForecastState, 1).active_run_id == active[0].id


def test_invalid_import_then_rollback_preserves_consistent_outlook(request):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0007")
    for name in ("first", "second"):
        assert (
            import_bundle(database.sessions, name, raw(bundle(name)), "sample").status == "active"
        )
    invalid = bundle("invalid")
    invalid["rows"][0]["p10"] = "-10"
    assert import_bundle(database.sessions, "invalid", raw(invalid), "sample").status == "staged"
    activate(database.sessions, "first", "sample")
    view = outlook(
        database.sessions, database.ids.authorization, database.ids.section, "cabbage", 1, "sample"
    )
    assert view.run_id == "first" and view.warning is not None


def test_migration_round_trip_preserves_existing_user_data(request):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0007")
    with database.sessions() as session:
        assert session.get(ForecastState, 1).active_run_id is None
    import_bundle(database.sessions, "sample-v1", raw(bundle()), "sample")
    command.downgrade(database.config, "0006")
    tables = inspect(database.engine).get_table_names(schema=database.schema)
    assert "forecast_state" not in tables and "forecast_runs" not in tables
    with database.sessions() as session:
        assert session.get(AuthIdentity, database.ids.owner).phone_verified
    command.upgrade(database.config, "0007")
    assert import_bundle(database.sessions, "sample-v1", raw(bundle()), "sample").status == "active"


def test_staging_outlook_smoke_uses_and_removes_postgres_session(request):
    from farmable_backend.config import Settings
    from farmable_backend.demo_seed import DEMO_OWNER_ID, seed_demo_farm
    from farmable_backend.integrations.settings import ServiceSettings
    from farmable_backend.main import create_app
    from farmable_backend.models import AuthSession
    from farmable_backend.outlook_smoke import SmokeConfig, smoke
    from farmable_backend.records_api import RecordRuntime
    from farmable_backend.records_service import RecordsService
    from fastapi.testclient import TestClient

    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0008")
    with database.sessions.begin() as session:
        seed_demo_farm(session)
        session.add(
            AuthIdentity(
                id=DEMO_OWNER_ID,
                first_name="Demo",
                surname="Farmer",
                phone="+27000000000",
                email="smoke@example.invalid",
                password_hash="not-a-password",  # noqa: S106 -- synthetic identity only.
                phone_verified=True,
                email_verified=True,
            )
        )
    import_bundle(database.sessions, "sample-v1", raw(bundle()), "sample")
    sha = "a" * 40
    app = create_app(
        Settings(forecast_data_mode="sample", commit_sha=sha),
        readiness=lambda: {"database": "ok", "worker": "ok"},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    app.state.records = RecordRuntime(RecordsService(database.sessions), lambda: None)
    config = SmokeConfig(
        environment="staging", mode="sample", api_url="https://demo.run.app", commit_sha=sha
    )
    with TestClient(app) as api:

        def handle(request):
            result = api.get(
                request.url.path, params=request.url.params, headers=dict(request.headers)
            )
            return httpx.Response(
                result.status_code, content=result.content, headers=dict(result.headers)
            )

        with httpx.Client(base_url=config.api_url, transport=httpx.MockTransport(handle)) as client:
            assert smoke(database.sessions, config, client) == 96
    with database.sessions() as session:
        assert (
            session.scalar(select(AuthSession).where(AuthSession.user_id == DEMO_OWNER_ID)) is None
        )
