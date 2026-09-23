"""Exercise the actual staging checker through the real authenticated HTTP route."""

from datetime import UTC, datetime
from pathlib import Path

import httpx
import pytest
from farmable_backend import outlook_smoke
from farmable_backend.demo_seed import DEMO_OWNER_ID, seed_demo_farm
from farmable_backend.forecast_cli import import_latest
from farmable_backend.models import AuthIdentity, AuthSession, Farm, ForecastState, Section
from farmable_backend.outlook_smoke import SmokeConfig, smoke
from farmable_backend.record_access import ApiError
from sqlalchemy import func, select

pytest_plugins = ("test_records_api",)
ROOT = Path(__file__).resolve().parents[3]


@pytest.fixture
def ready(records):
    with records.sessions.begin() as session:
        seed_demo_farm(session)
        session.add(
            AuthIdentity(
                id=DEMO_OWNER_ID,
                first_name="Demo",
                surname="Farmer",
                phone="+27000000000",
                email="smoke@example.invalid",
                password_hash="not-a-password",  # noqa: S106 -- no password login in fixture.
                phone_verified=True,
                email_verified=True,
            )
        )
        session.add(ForecastState(id=1))
    import_latest(records.sessions, ROOT / "ml/forecast/fixtures", "sample")
    records.app.state.forecast_data_mode = "sample"
    health = records.client.get("/health/ready").json()
    config = SmokeConfig(
        environment="staging", mode="sample", api_url="https://demo.run.app", commit_sha="a" * 40
    )
    health["sha"] = config.commit_sha
    calls = []

    def handle(request):
        calls.append(request)
        if request.url.path == "/health/ready":
            return httpx.Response(200, json=health)
        result = records.client.get(
            request.url.path, params=request.url.params, headers=dict(request.headers)
        )
        return httpx.Response(
            result.status_code, content=result.content, headers=dict(result.headers)
        )

    with httpx.Client(base_url=config.api_url, transport=httpx.MockTransport(handle)) as client:
        yield records, config, client, calls


def counts(records):
    with records.sessions() as session:
        return tuple(
            session.scalar(select(func.count()).select_from(model))
            for model in (AuthSession, AuthIdentity, Farm, Section)
        )


def test_outlook_present_for_all_demo_crops(ready):
    records, config, client, calls = ready
    before = counts(records)
    assert smoke(records.sessions, config, client) == 96
    assert len(calls) == 98  # health, authentication denial, 96 authenticated requests
    assert counts(records) == before
    # The temporary credential cannot be reused after completion.
    assert (
        records.client.get(
            "/outlook", params=calls[-1].url.params, headers=dict(calls[-1].headers)
        ).status_code
        == 401
    )


@pytest.mark.parametrize("state", ["unverified", "missing", "foreign", "deleted"])
def test_smoke_never_creates_or_verifies_demo_identity(ready, state):
    records, config, client, calls = ready
    with records.sessions.begin() as session:
        if state == "missing":
            session.delete(session.get(AuthIdentity, DEMO_OWNER_ID))
        elif state == "unverified":
            session.get(AuthIdentity, DEMO_OWNER_ID).phone_verified = False
        elif state == "foreign":
            session.get(Farm, outlook_smoke.DEMO_FARM_ID).owner_id = records.ids.other
        else:
            session.get(Section, outlook_smoke.DEMO_CABBAGE_SECTION_ID).deleted_at = datetime.now(
                UTC
            )
    before = counts(records)
    with pytest.raises((ValueError, ApiError)):
        smoke(records.sessions, config, client)
    assert counts(records) == before
    assert len(calls) == 2


@pytest.mark.parametrize(
    "failure",
    [
        "http",
        "redirect",
        "schema",
        "negative",
        "nan",
        "wrong_crop",
        "sample_warning",
        "run_switch",
        "oversized",
        "cache",
        "timeout",
    ],
)
def test_smoke_fails_and_removes_credential_on_bad_outlook(ready, failure):
    records, config, original, _ = ready
    before = counts(records)
    seen = 0

    def handle(request):
        nonlocal seen
        response = original.send(request)
        if request.url.path != "/outlook" or not request.headers.get("authorization"):
            return response
        seen += 1
        if failure == "http":
            return httpx.Response(503, json={"error": "unavailable"})
        if failure == "redirect":
            return httpx.Response(302, headers={"Location": "https://other.run.app"}, json={})
        if failure == "timeout":
            raise httpx.ReadTimeout("PRIVATE PROVIDER DETAIL")
        if failure == "oversized":
            return httpx.Response(200, content=b"x" * 65_537)
        body = response.json()
        if failure == "schema":
            del body["price_range"]
        elif failure == "negative":
            body["price_range"]["p10"] = "-1"
        elif failure == "nan":
            body["cost_per_ha"] = "NaN"
        elif failure == "wrong_crop":
            body["crop"] = "tomatoes"
        elif failure == "sample_warning":
            body["warning"] = None
        elif failure == "run_switch" and seen > 1:
            body["run_id"] = "other-run"
        return httpx.Response(
            200,
            json=body,
            headers={"cache-control": "public" if failure == "cache" else "no-store"},
        )

    with httpx.Client(base_url=config.api_url, transport=httpx.MockTransport(handle)) as client:
        with pytest.raises((ValueError, httpx.ReadTimeout)):
            smoke(records.sessions, config, client)
    assert counts(records) == before


def test_smoke_rejects_sample_data_in_historical_mode(ready):
    records, config, client, _ = ready
    config.mode = "historical"
    before = counts(records)
    with pytest.raises(ValueError, match="historical_kind"):
        smoke(records.sessions, config, client)
    assert counts(records) == before


@pytest.mark.parametrize(
    "updates",
    [
        {"environment": "production"},
        {"mode": "disabled"},
        {"api_url": "http://demo.run.app"},
        {"api_url": "https://demo.run.app.attacker.com"},
        {"api_url": "https://demo.run.app/path"},
    ],
)
def test_smoke_rejects_unsafe_configuration(ready, updates):
    _, config, _, _ = ready
    with pytest.raises(ValueError):
        SmokeConfig.model_validate({**config.model_dump(), **updates})


def test_smoke_cli_does_not_print_exception_or_credentials(monkeypatch, capsys):
    monkeypatch.setenv("ENVIRONMENT", "staging")
    monkeypatch.setenv("FORECAST_DATA_MODE", "sample")
    monkeypatch.setenv("OUTLOOK_SMOKE_API_URL", "https://demo.run.app")
    monkeypatch.setenv("COMMIT_SHA", "a" * 40)
    monkeypatch.setenv("DATABASE_URL", "postgresql+psycopg://u:PRIVATE_PASSWORD@localhost/db")

    def fail(*args):
        raise RuntimeError("PRIVATE_TOKEN PRIVATE_PASSWORD")

    monkeypatch.setattr(outlook_smoke, "Database", fail)
    assert outlook_smoke.main() == 1
    output = capsys.readouterr()
    assert "FAIL:" in output.out
    assert "PRIVATE" not in output.out + output.err


@pytest.mark.parametrize("case", ["wrong_revision", "auth_bypassed"])
def test_smoke_checks_revision_and_auth_before_creating_session(ready, case):
    records, config, original, _ = ready
    before = counts(records)

    def handle(request):
        if case == "wrong_revision":
            return httpx.Response(200, json={"sha": "b" * 40})
        if request.url.path == "/outlook":
            return httpx.Response(200, json={}, headers={"cache-control": "no-store"})
        return original.send(request)

    with httpx.Client(base_url=config.api_url, transport=httpx.MockTransport(handle)) as client:
        with pytest.raises(ValueError, match="smoke_wrong_revision|smoke_auth_required"):
            smoke(records.sessions, config, client)
    assert counts(records) == before


def test_cloud_run_regional_hostname_is_supported():
    config = SmokeConfig(
        environment="staging",
        mode="historical",
        api_url="https://demo-abc-uc.a.run.app",
        commit_sha="a" * 40,
    )
    assert config.api_url.endswith(".a.run.app")
