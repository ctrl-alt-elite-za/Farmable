import ast
import asyncio
from pathlib import Path

import pytest
from farmable_backend import forecast_cli, manage
from farmable_backend.config import DatabaseSettings, ProxySettings, Settings
from pydantic import SecretStr, ValidationError


@pytest.mark.parametrize("value", ["", "   ", "replace-with-a-local-secret"])
def test_export_token_secret_rejects_empty_and_example_placeholders(value: str) -> None:
    with pytest.raises(ValidationError, match="EXPORT_TOKEN_SECRET"):
        Settings(
            database_url=SecretStr("postgresql+psycopg://unit:unit@localhost/unit"),
            export_token_secret=SecretStr(value),
        )


def test_trusted_proxy_hops_defaults_to_socket_peer_only(monkeypatch) -> None:
    monkeypatch.delenv("TRUSTED_PROXY_HOPS", raising=False)
    assert ProxySettings().trusted_proxy_hops == 0
    monkeypatch.setenv("TRUSTED_PROXY_HOPS", "1")
    assert ProxySettings().trusted_proxy_hops == 1


@pytest.mark.parametrize("value", ["-1", "3", "many"])
def test_trusted_proxy_hops_rejects_out_of_range(monkeypatch, value: str) -> None:
    monkeypatch.setenv("TRUSTED_PROXY_HOPS", value)
    with pytest.raises(ValidationError):
        ProxySettings()


@pytest.fixture
def job_environment(monkeypatch):
    # The staging migration and forecast-import Cloud Run jobs receive only
    # DATABASE_URL (plus their own tokens); never the export signing secret.
    monkeypatch.delenv("EXPORT_TOKEN_SECRET", raising=False)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://unit:unit@localhost/unit")


def test_database_settings_do_not_need_the_export_secret(job_environment) -> None:
    assert DatabaseSettings().database_url.get_secret_value().endswith("/unit")
    assert "export_token_secret" not in DatabaseSettings.model_fields
    with pytest.raises(ValidationError, match="export_token_secret"):
        Settings()


def test_migrations_build_their_engine_from_database_settings() -> None:
    env = ast.parse((Path(__file__).parents[3] / "migrations" / "env.py").read_text())
    called = {
        node.func.id
        for node in ast.walk(env)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
    }
    assert "DatabaseSettings" in called
    assert "Settings" not in called


def test_queue_schema_starts_without_the_export_secret(job_environment, monkeypatch) -> None:
    seen = []

    def stop(settings):
        seen.append(settings)
        raise RuntimeError("stop before connecting")

    monkeypatch.setattr(manage, "create_task_app", stop)
    with pytest.raises(RuntimeError, match="stop before connecting"):
        asyncio.run(manage.run("queue-schema"))
    assert len(seen) == 1


def test_forecast_import_starts_without_the_export_secret(job_environment, monkeypatch) -> None:
    monkeypatch.setenv("FORECAST_DATA_MODE", "sample")
    seen = []

    def stop(config):
        seen.append(config.forecast_data_mode)
        raise RuntimeError("stop before connecting")

    monkeypatch.setattr(forecast_cli, "Database", stop)
    assert forecast_cli.main(["import-latest"]) == 0
    assert seen == ["sample"]
