import asyncio
from unittest.mock import MagicMock, patch
from uuid import uuid4

import pytest
from farmable_backend.config import Settings
from farmable_backend.database import Database, live_worker, make_engine
from farmable_backend.logging import request_id
from farmable_backend.models import Base
from farmable_backend.tasks import create_task_app
from pydantic import SecretStr, ValidationError


def test_only_owned_application_tables_are_registered():
    assert set(Base.metadata.tables) == {
        "account_profiles",
        "detector_models",
        "weight_formulas",
        "users",
        "farms",
        "sections",
        "plantings",
        "media",
        "observations",
        "farm_tasks",
        "financial_records",
        "saved_plans",
        "sync_mutations",
        "sync_changes",
        "verification_challenges",
        "auth_sessions",
        "auth_identities",
        "photo_uploads",
        "photo_attempts",
        "photo_rates",
        "voice_session_rates",
        "forecast_runs",
        "forecast_state",
        "weather_jobs",
        "weather_risk_climatology",
        "reference_imports",
        "reference_market_prices",
        "reference_crop_calendars",
        "reference_crop_costs",
    }


def test_query_timeout(settings):
    with patch("farmable_backend.database.create_engine") as create:
        make_engine(settings)
    assert create.call_args.kwargs["connect_args"] == {
        "connect_timeout": 5,
        "options": "-c statement_timeout=5000 -c search_path=public",
    }
    assert create.call_args.kwargs["hide_parameters"] is True


def test_migration_connections_bound_lock_waits(settings):
    with patch("farmable_backend.database.create_engine") as create:
        make_engine(settings, migration=True)
    assert create.call_args.kwargs["connect_args"] == {
        "connect_timeout": 5,
        "options": "-c statement_timeout=5000 -c search_path=public -c lock_timeout=1000",
    }


@pytest.mark.parametrize(
    "url", ["sqlite://", "postgresql://a:b@host/db", "postgresql+psycopg://a@host/db", "invalid"]
)
def test_credentials_required_from_environment(url):
    with pytest.raises(ValidationError):
        Settings(database_url=SecretStr(url))


def test_database_failure_is_safe(settings):
    database = Database(settings)
    database.sessions = MagicMock(side_effect=RuntimeError("credential"))
    assert database.readiness() == {"database": "down", "worker": "down"}
    database.close()


def test_missing_worker_is_down(settings):
    database = Database(settings)
    session = MagicMock()
    session.scalar.side_effect = [object(), None]
    database.sessions = MagicMock()
    database.sessions.return_value.__enter__.return_value = session
    assert database.readiness() == {"database": "ok", "worker": "down"}
    database.close()


def test_worker_check_is_orm_and_bounded():
    session = MagicMock()
    session.scalar.return_value = None
    assert not live_worker(session)
    statement = session.scalar.call_args.args[0]
    assert statement._limit_clause.value == 1
    assert "last_heartbeat" in str(statement)


def test_worker_shares_example_task(settings):
    app = create_task_app(settings)
    assert "example_job" in app.tasks
    assert app.tasks["example_job"].queue == "default"
    assert app.connector._pool_args["kwargs"] == {
        "connect_timeout": 5,
        "options": "-c statement_timeout=5000 -c search_path=public",
    }


def test_example_job_preserves_request_context(settings):
    app = create_task_app(settings)
    rid = str(uuid4())
    observed = []
    with patch("farmable_backend.tasks.logging.getLogger") as get_logger:
        get_logger.return_value.info.side_effect = lambda message: observed.append(request_id.get())
        asyncio.run(app.tasks["example_job"](request_id_value=rid))
    assert observed == [rid]
    assert request_id.get() == "system"
