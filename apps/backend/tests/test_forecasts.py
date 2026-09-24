"""Synthetic snapshots exercise the actual importer and authenticated outlook API."""

import hashlib
import io
import json
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from farmable_backend import forecast_cli
from farmable_backend.forecast_contract import CROPS, SAMPLE_WARNING, ForecastBundle
from farmable_backend.forecasts import activate, import_bundle
from farmable_backend.models import Farm, ForecastRun, ForecastState, Section
from farmable_backend.record_access import ApiError
from sqlalchemy import func, select
from test_farm_schema import _index_statements, _orm_sql, _table_elements

pytest_plugins = ("test_records_api",)
ROOT = Path(__file__).resolve().parents[3]
FIXTURES = ROOT / "ml/forecast/fixtures"
REAL_RUN_ID = "5310d438e67b5333c22786a9b727f8c78fda671314677af9f77c59d131bd952d"
REAL_FORECAST = ROOT / "ml/forecast/results" / REAL_RUN_ID / "forecast.json"


def bundle(run_id="sample-v1"):
    value = json.loads((FIXTURES / "sample-v1/forecast.json").read_bytes())
    value["run_id"] = run_id
    return value


def raw(value):
    return json.dumps(value, sort_keys=True).encode()


@pytest.fixture
def forecasts(records):
    with records.sessions.begin() as session:
        session.add(ForecastState(id=1))
    records.app.state.forecast_data_mode = "sample"
    return records


def get_outlook(forecasts, **kwargs):
    return forecasts.client.get(
        "/outlook",
        params={
            "section_id": str(forecasts.ids.section),
            "crop": "cabbage",
            "plant_month": 1,
            **kwargs,
        },
    )


def test_committed_fixture_is_complete_and_source_hash_matches():
    parsed = ForecastBundle.model_validate(bundle())
    assert parsed.data_kind == "synthetic"
    assert (
        parsed.sources[0].sha256
        == hashlib.sha256((FIXTURES / "sample_inputs.json").read_bytes()).hexdigest()
    )
    assert {(row.crop, row.plant_month) for row in parsed.rows} == {
        (crop, month) for crop in CROPS for month in range(1, 13)
    }


def test_retrospective_import_requires_explicit_mode_and_displays_caveat(forecasts):
    from farmable_backend.forecast_contract import RETROSPECTIVE_WARNING

    value = bundle("retrospective-fixture")
    value["data_kind"] = "retrospective"
    for row in value["rows"]:
        row["method"] = "historical_range"
    rejected = import_bundle(forecasts.sessions, value["run_id"], raw(value), "historical")
    assert "data_mode_mismatch" in rejected.failed_checks
    value["run_id"] = "retrospective-accepted"
    accepted = import_bundle(forecasts.sessions, value["run_id"], raw(value), "retrospective")
    assert accepted.status == "active"
    forecasts.app.state.forecast_data_mode = "retrospective"
    response = get_outlook(forecasts)
    assert response.status_code == 200
    assert response.json()["data_kind"] == "retrospective"
    assert response.json()["warning"] == RETROSPECTIVE_WARNING


def test_real_retrospective_artifact_imports_and_serves_outlook(forecasts):
    from farmable_backend.forecast_contract import RETROSPECTIVE_WARNING

    content = REAL_FORECAST.read_bytes()
    first = import_bundle(forecasts.sessions, REAL_RUN_ID, content, "retrospective")
    assert first.status == "active"
    assert first.failed_checks == ()
    second = import_bundle(forecasts.sessions, REAL_RUN_ID, content, "retrospective")
    assert second.status == "active"
    forecasts.app.state.forecast_data_mode = "retrospective"
    response = get_outlook(forecasts)
    assert response.status_code == 200
    assert response.json()["data_kind"] == "retrospective"
    assert response.json()["warning"] == RETROSPECTIVE_WARNING
    forecasts.app.state.forecast_data_mode = "historical"
    assert get_outlook(forecasts).status_code == 503


def test_import_latest_activates_valid_run_and_serves_all_crop_months(forecasts):
    result = forecast_cli.import_latest(forecasts.sessions, FIXTURES, "sample")
    assert [(item.run_id, item.status) for item in result] == [("sample-v1", "active")]
    for crop in CROPS:
        for month in range(1, 13):
            response = get_outlook(forecasts, crop=crop, plant_month=month)
            assert response.status_code == 200
            view = response.json()
            assert view["crop"] == crop and view["plant_month"] == month
            assert view["run_id"] == "sample-v1" and view["data_kind"] == "synthetic"
            assert view["warning"] == SAMPLE_WARNING
            assert view["weather_risk"]["status"] == "unavailable"
            assert response.headers["cache-control"] == "no-store"


def test_arithmetic_and_harvest_month_wrap(forecasts):
    import_bundle(forecasts.sessions, "sample-v1", raw(bundle()), "sample")
    view = get_outlook(forecasts, plant_month=11).json()
    assert view["harvest_month"] == 2
    assert Decimal(view["break_even_price_per_kg"]) == Decimal("3.75")
    assert Decimal(view["price_range"]["p50"]) == Decimal("6")
    assert view["price_range"]["unit"] == "ZAR/kg"
    assert view["price_basis_year"] == 2025 and view["method"] == "fixture"


def test_import_idempotent_and_changed_bytes_do_not_overwrite_active(forecasts):
    data = bundle()
    assert import_bundle(forecasts.sessions, "sample-v1", raw(data), "sample").status == "active"
    assert import_bundle(forecasts.sessions, "sample-v1", raw(data), "sample").status == "active"
    data["rows"][0]["p50"] = "999"
    conflict = import_bundle(forecasts.sessions, "sample-v1", raw(data), "sample")
    assert conflict.failed_checks == ("run_id_conflict",)
    with forecasts.sessions() as session:
        assert session.scalar(select(func.count()).select_from(ForecastRun)) == 1
        assert session.get(ForecastState, 1).active_run_id == "sample-v1"


@pytest.mark.parametrize(
    "case,check",
    [
        ("negative", "prices_positive"),
        ("unordered", "quantiles_ordered"),
        ("missing", "crop_month_coverage"),
        ("duplicate", "crop_month_coverage"),
        ("unknown_crop", "schema"),
        ("month_zero", "schema"),
        ("nan", "schema"),
        ("zero_yield", "schema"),
        ("unknown_field", "schema"),
        ("wrong_run", "run_id_mismatch"),
        ("future", "as_of_future"),
        ("old", "as_of_regression"),
        ("mode", "data_mode_mismatch"),
        ("method", "method_kind_mismatch"),
    ],
)
def test_invalid_run_stays_staged_and_previous_stays_active(forecasts, case, check, tmp_path):
    import_bundle(forecasts.sessions, "sample-v1", raw(bundle()), "sample")
    data = bundle("invalid")
    row = data["rows"][0]
    if case == "negative":
        row["p10"] = "-1"
    elif case == "unordered":
        row["p90"] = "1"
    elif case == "missing":
        data["rows"].pop()
    elif case == "duplicate":
        data["rows"][-1] = dict(row)
    elif case == "unknown_crop":
        row["crop"] = "beetroot"
    elif case == "month_zero":
        row["plant_month"] = 0
    elif case == "nan":
        row["p50"] = "NaN"
    elif case == "zero_yield":
        row["yield_kg_per_ha"] = "0"
    elif case == "unknown_field":
        data["private-secret"] = "never-report-me"
    elif case == "wrong_run":
        data["run_id"] = "different"
    elif case == "future":
        data["as_of"] = "2099-01-01T00:00:00Z"
    elif case == "old":
        data["as_of"] = "2020-01-01T00:00:00Z"
    elif case == "mode":
        data["data_kind"] = "historical"
    elif case == "method":
        row["method"] = "lightgbm"
    folder = tmp_path / "invalid"
    folder.mkdir()
    (folder / "forecast.json").write_bytes(raw(data))
    notices = []
    results = forecast_cli.import_latest(forecasts.sessions, tmp_path, "sample", notices.append)
    assert results[0].status == "staged" and check in results[0].failed_checks
    assert notices == results and "never-report-me" not in repr(notices)
    with forecasts.sessions() as session:
        assert session.get(ForecastState, 1).active_run_id == "sample-v1"
        assert session.get(ForecastRun, "sample-v1").status == "active"
        assert session.get(ForecastRun, "invalid").status == "staged"
    assert get_outlook(forecasts).json()["run_id"] == "sample-v1"


def test_50_percent_jump_boundary_and_rollback(forecasts):
    import_bundle(forecasts.sessions, "sample-v1", raw(bundle()), "sample")
    data = bundle("sample-v2")
    for row in data["rows"]:
        for field in ("p10", "p50", "p90"):
            row[field] = str(Decimal(row[field]) * Decimal("1.5"))
    assert import_bundle(forecasts.sessions, "sample-v2", raw(data), "sample").status == "active"
    assert get_outlook(forecasts).json()["run_id"] == "sample-v2"
    data["run_id"] = "sample-v3"
    data["rows"][0].update(p50="1000", p90="2000")
    assert (
        "p50_jump"
        in import_bundle(forecasts.sessions, "sample-v3", raw(data), "sample").failed_checks
    )
    with pytest.raises(ApiError, match="forecast_not_previously_active"):
        activate(forecasts.sessions, "sample-v3", "sample")
    activate(forecasts.sessions, "sample-v1", "sample")
    assert get_outlook(forecasts).json()["run_id"] == "sample-v1"
    # A normal reimport must never undo an explicit rollback.
    data = bundle("sample-v2")
    for row in data["rows"]:
        for field in ("p10", "p50", "p90"):
            row[field] = str(Decimal(row[field]) * Decimal("1.5"))
    assert (
        import_bundle(forecasts.sessions, "sample-v2", raw(data), "sample").status == "superseded"
    )
    assert get_outlook(forecasts).json()["run_id"] == "sample-v1"


@pytest.mark.parametrize("section", ["foreign_section", "missing"])
def test_outlook_other_farm_404_even_without_an_active_forecast(forecasts, section):
    target = uuid4() if section == "missing" else forecasts.ids.foreign_section
    assert get_outlook(forecasts, section_id=str(target)).status_code == 404


@pytest.mark.parametrize("kind", ["farm", "section"])
def test_deleted_entities_are_not_visible(forecasts, kind):
    with forecasts.sessions.begin() as session:
        entity = (
            session.get(Farm, forecasts.ids.farm)
            if kind == "farm"
            else session.get(Section, forecasts.ids.section)
        )
        entity.deleted_at = datetime.now(UTC)
    assert get_outlook(forecasts).status_code == 404


def test_unauthenticated_outlook_rejected(forecasts):
    forecasts.client.headers.pop("authorization")
    assert get_outlook(forecasts).status_code == 401


def test_no_forecast_is_explicit_unavailability(forecasts):
    response = get_outlook(forecasts)
    assert (
        response.status_code == 503 and response.json()["error"]["code"] == "forecast_unavailable"
    )


@pytest.mark.parametrize("mode", ["historical", "disabled"])
def test_sample_snapshot_cannot_leak_through_other_modes(forecasts, mode):
    import_bundle(forecasts.sessions, "sample-v1", raw(bundle()), "sample")
    forecasts.app.state.forecast_data_mode = mode
    assert get_outlook(forecasts).status_code == 503
    with pytest.raises(ApiError, match="forecast_mode_mismatch"):
        activate(forecasts.sessions, "sample-v1", mode)


def test_historical_metadata_is_supported_without_claiming_fixture_accuracy(forecasts):
    data = bundle("historical-contract-test")
    data["data_kind"] = "historical"
    for row in data["rows"]:
        row["method"] = "historical_range"
    assert (
        import_bundle(forecasts.sessions, data["run_id"], raw(data), "historical").status
        == "active"
    )
    forecasts.app.state.forecast_data_mode = "historical"
    view = get_outlook(forecasts).json()
    assert view["data_kind"] == "historical" and view["warning"] is None
    # This only exercises a metadata contract. It is not committed as real results.
    assert "invented test inputs" in view["assumptions"][0]


def test_weather_unavailable_makes_no_provider_call(forecasts):
    import_bundle(forecasts.sessions, "sample-v1", raw(bundle()), "sample")
    forecasts.app.state.services.open_meteo.settings.fault_open_meteo = True
    assert get_outlook(forecasts).json()["weather_risk"] == {
        "status": "unavailable",
        "reasons": ["climatology_not_computed"],
    }
    assert not forecasts.app.state.services.transport.calls


@pytest.mark.parametrize(
    "params", [{"crop": "pumpkins"}, {"plant_month": 0}, {"plant_month": 13}, {"model": "other"}]
)
def test_invalid_query_rejected(forecasts, params):
    assert get_outlook(forecasts, **params).status_code == 422


def test_duplicate_query_rejected(forecasts):
    response = forecasts.client.get(
        "/outlook",
        params=[
            ("section_id", str(forecasts.ids.section)),
            ("crop", "cabbage"),
            ("crop", "spinach"),
            ("plant_month", "1"),
        ],
    )
    assert response.status_code == 422


def test_disabled_import_does_not_consume_run_ids(forecasts):
    assert forecast_cli.import_latest(forecasts.sessions, FIXTURES, "disabled") == []
    with forecasts.sessions() as session:
        assert session.scalar(select(func.count()).select_from(ForecastRun)) == 0


def test_import_failure_and_notification_failure_do_not_stop_other_runs(
    forecasts, tmp_path, capsys
):
    (tmp_path / "a-missing").mkdir()
    folder = tmp_path / "sample-v1"
    folder.mkdir()
    (folder / "forecast.json").write_bytes(raw(bundle()))

    def unavailable_notification(result):
        raise RuntimeError("private-notification-token")

    results = forecast_cli.import_latest(
        forecasts.sessions, tmp_path, "sample", unavailable_notification
    )
    assert results[0].failed_checks == ("artifact_missing",)
    assert results[1].status == "active"
    output = capsys.readouterr().out
    assert "notification_failed" in output and "private-notification-token" not in output


def test_deploy_continues_when_import_fails(monkeypatch, settings, capsys):
    monkeypatch.setattr(
        forecast_cli,
        "Settings",
        lambda: settings.model_copy(update={"forecast_data_mode": "sample"}),
    )

    def unavailable(config):
        raise RuntimeError("private-db-password")

    monkeypatch.setattr(forecast_cli, "Database", unavailable)
    assert forecast_cli.main(["import-latest"]) == 0
    assert forecast_cli.main(["activate", "--run", "sample-v1"]) == 1
    output = capsys.readouterr().out
    assert "command_failed" in output and "private-db-password" not in output


def test_large_and_invalid_artifacts_do_not_publish(forecasts, tmp_path):
    folder = tmp_path / "large"
    folder.mkdir()
    (folder / "forecast.json").write_bytes(b"x" * 1_048_577)
    assert forecast_cli.import_latest(forecasts.sessions, tmp_path, "sample")[0].failed_checks == (
        "bundle_too_large",
    )
    assert import_bundle(forecasts.sessions, "malformed", b"not JSON", "sample").failed_checks == (
        "schema",
    )


def test_openapi_declares_snapshot_and_auth(forecasts):
    route = forecasts.app.openapi()["paths"]["/outlook"]["get"]
    assert route["security"] == [{"SessionBearer": []}]
    assert set(route["responses"]) >= {"200", "401", "404", "422", "503"}


def test_migration_matches_orm_and_seeds_singleton():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0006:0007", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql and "DROP TABLE" not in sql
    assert "SERIAL" not in sql  # The singleton is explicitly id=1, not a sequence.
    for table in ("forecast_runs", "forecast_state"):
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)
        assert _index_statements(sql, table) == _index_statements(_orm_sql(table), table)
    assert "INSERT INTO forecast_state (id, active_run_id) VALUES (1, NULL)" in sql
