"""Credential contracts use isolated transports; never open a paid Live session."""

import asyncio
import io
import json
from datetime import UTC, datetime, timedelta

import httpx
import pytest
from alembic import command
from alembic.config import Config
from farmable_backend.integrations.gemini_live import GeminiLive
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.models import AuthIdentity, AuthSession, VoiceSessionRate
from farmable_backend.record_access import ApiError, db_now
from farmable_backend.voice_api import LiveSessionResponse, admit
from pydantic import SecretStr
from sqlalchemy import select
from test_farm_schema import _orm_sql, _table_elements
from test_records_api import records  # noqa: F401 -- shared authenticated HTTP/ORM fixture

PATH = "/voice/live-session"


@pytest.fixture
def voice(records):  # noqa: F811 -- pytest injects the imported shared fixture
    config = records.app.state.services.gemini_live.settings
    config.gemini_live_enabled = True
    config.gemini_live_model = "fixture-live-model"
    return records


def test_authenticated_fake_credential_is_short_lived_and_not_logged(voice, caplog):
    before = datetime.now(UTC)
    response = voice.client.post(PATH)
    assert response.status_code == 200
    result = LiveSessionResponse.model_validate(response.json())
    assert result.mode == "fake" and result.api_version == "v1beta"
    assert result.credential == "auth_tokens/fixture-only-not-a-live-token"
    assert result.model == "models/fixture-live-model"
    assert before + timedelta(seconds=60) <= result.new_session_expires_at
    assert result.new_session_expires_at <= datetime.now(UTC) + timedelta(seconds=60)
    assert result.expires_at - result.new_session_expires_at == timedelta(minutes=9)
    assert response.headers["cache-control"] == "no-store"
    assert result.credential not in repr(result) + caplog.text
    assert voice.ids.authorization not in caplog.text


@pytest.mark.parametrize("authorization", [None, "Bearer invalid", "Bearer " + "z" * 43])
def test_missing_or_wrong_session_never_calls_provider(voice, authorization):
    voice.client.headers.pop("authorization", None)
    headers = {} if authorization is None else {"authorization": authorization}
    response = voice.client.post(PATH, headers=headers)
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"
    assert not voice.app.state.services.transport.calls


@pytest.mark.parametrize("invalid", ["expired", "revoked", "phone", "email"])
def test_expired_revoked_or_unverified_session_is_rejected(voice, invalid):
    with voice.sessions.begin() as session:
        if invalid in {"expired", "revoked"}:
            row = session.scalar(select(AuthSession))
            if invalid == "expired":
                row.expires_at = datetime.now(UTC) - timedelta(seconds=1)
            else:
                row.revoked_at = datetime.now(UTC)
        else:
            identity = session.get(AuthIdentity, voice.ids.owner)
            setattr(identity, invalid + "_verified", False)
    assert voice.client.post(PATH).status_code == 401
    assert not voice.app.state.services.transport.calls


def test_duplicate_authorization_rejected(voice):
    response = voice.client.post(
        PATH,
        headers=[("authorization", voice.ids.authorization), ("authorization", "Bearer other")],
    )
    assert response.status_code == 401
    assert not voice.app.state.services.transport.calls


@pytest.mark.parametrize("missing", ["flag", "model", "mode", "key"])
def test_incomplete_configuration_fails_closed(voice, missing):
    config = voice.app.state.services.gemini_live.settings
    if missing == "flag":
        config.gemini_live_enabled = False
    elif missing == "model":
        config.gemini_live_model = None
    elif missing == "mode":
        config.integrations_mode = "disabled"
    else:
        # Transport remains isolated while exercising live key validation.
        config.integrations_mode = "live"
        config.gemini_api_key = None
    response = voice.client.post(PATH)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "voice_disabled"
    assert not voice.app.state.services.transport.calls
    with voice.sessions() as session:
        assert session.get(VoiceSessionRate, voice.ids.owner) is None


@pytest.mark.parametrize(
    "body", [b"{}", b'{"uses":0}', b"x" * 100_000], ids=["empty-json", "override", "large"]
)
def test_no_caller_policy_or_body_is_accepted(voice, body):
    assert voice.client.post(PATH, content=body).status_code == 422
    assert not voice.app.state.services.transport.calls


def test_no_query_overrides(voice):
    assert voice.client.post(PATH + "?model=other&uses=0").status_code == 422
    assert not voice.app.state.services.transport.calls


def test_limits_are_durable_and_attempts_not_refunded(voice):
    voice.app.state.services.transport.modes["gemini"] = "error"
    for _ in range(3):
        response = voice.client.post(PATH)
        assert response.status_code == 503
        assert response.json()["error"]["code"] == "voice_unavailable"
    response = voice.client.post(PATH)
    assert response.status_code == 429
    assert 1 <= int(response.headers["retry-after"]) <= 60
    assert voice.app.state.services.transport.calls["gemini"] == 3
    # Fresh invocation sees the same persisted quota, not per-process memory.
    with pytest.raises(ApiError) as error:
        admit(voice.sessions, voice.ids.authorization, True)
    assert error.value.code == "voice_rate_limited"


def test_hourly_limit_and_expired_history(voice):
    with voice.sessions.begin() as session:
        now = db_now(session).timestamp()
        session.add(VoiceSessionRate(owner_id=voice.ids.owner, hits=[now - 120] * 20))
    response = voice.client.post(PATH)
    assert response.status_code == 429
    assert 3400 < int(response.headers["retry-after"]) <= 3480
    with voice.sessions.begin() as session:
        session.get(VoiceSessionRate, voice.ids.owner).hits = [now - 3601] * 20
    assert voice.client.post(PATH).status_code == 200
    with voice.sessions() as session:
        assert len(session.get(VoiceSessionRate, voice.ids.owner).hits) == 1


@pytest.mark.parametrize("failure", ["slow", "fault"])
def test_timeout_and_fault_are_safe(voice, failure):
    adapter = voice.app.state.services.gemini_live
    adapter.timeout = 0.01
    if failure == "slow":
        voice.app.state.services.transport.modes["gemini"] = "slow"
    else:
        adapter.settings.fault_gemini = True
    response = voice.client.post(PATH)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == (
        "voice_timeout" if failure == "slow" else "voice_unavailable"
    )
    assert voice.app.state.services.transport.calls["gemini"] == (failure == "slow")


def test_rest_policy_and_long_lived_key_never_returned():
    async def run():
        key = "synthetic-server-key-not-a-real-credential"
        config = ServiceSettings(
            environment="staging",
            integrations_mode="live",
            gemini_live_enabled=True,
            gemini_live_model="fixture-live-model",
            gemini_api_key=SecretStr(key),
        )
        requests = []

        def respond(request):
            requests.append(request)
            return httpx.Response(200, json={"name": "auth_tokens/opaque-fixture", "apiKey": key})

        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            adapter = GeminiLive(client, config)
            result = await adapter.issue()
        assert result.ok and result.data["mode"] == "live"
        assert key not in str(result.data) + repr(result) + repr(config)
        assert len(requests) == 1
        request = requests[0]
        assert str(request.url) == "https://generativelanguage.googleapis.com/v1beta/auth_tokens"
        assert request.headers["x-goog-api-key"] == key
        policy = json.loads(request.content)
        assert policy["uses"] == 1 and "fieldMask" not in policy
        assert policy["bidiGenerateContentSetup"] == {
            "model": "models/fixture-live-model",
            "generationConfig": {"responseModalities": ["AUDIO"]},
            "sessionResumption": {},
        }
        assert datetime.fromisoformat(policy["expireTime"]) == result.data["expires_at"]
        assert (
            datetime.fromisoformat(policy["newSessionExpireTime"])
            == result.data["new_session_expires_at"]
        )

    asyncio.run(run())


@pytest.mark.parametrize(
    "payload",
    [
        {},
        {"name": 1},
        {"name": ""},
        {"name": "auth_tokens/fixture-key"},
        {"name": "auth_tokens/with whitespace"},
        {"name": "a" * 9000},
        [],
    ],
)
def test_invalid_provider_responses_trip_circuit_without_retry(payload):
    async def run():
        calls = []

        def respond(request):
            calls.append(request)
            return httpx.Response(200, json=payload)

        config = ServiceSettings(
            environment="ci",
            integrations_mode="fake",
            gemini_live_enabled=True,
            gemini_live_model="fixture-model",
        )
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            adapter = GeminiLive(client, config)
            for _ in range(5):
                result = await adapter.issue()
                assert result.error == "invalid_response" and result.data is None
            assert (await adapter.issue()).error == "unavailable"
        assert len(calls) == 5

    asyncio.run(run())


def test_bounded_concurrency_and_cancel_releases_slot():
    async def run():
        started = asyncio.Event()
        release = asyncio.Event()
        count = 0

        async def respond(request):
            nonlocal count
            count += 1
            if count == 4:
                started.set()
            await release.wait()
            return httpx.Response(200, json={"name": "auth_tokens/opaque-fixture"})

        config = ServiceSettings(
            environment="ci",
            integrations_mode="fake",
            gemini_live_enabled=True,
            gemini_live_model="fixture-model",
        )
        async with httpx.AsyncClient(transport=httpx.MockTransport(respond)) as client:
            adapter = GeminiLive(client, config)
            pending = [asyncio.create_task(adapter.issue()) for _ in range(4)]
            try:
                await asyncio.wait_for(started.wait(), 2)
                assert (await adapter.issue()).error == "capacity"
                pending[0].cancel()
                with pytest.raises(asyncio.CancelledError):
                    await pending[0]
                release.set()
                assert (await adapter.issue()).ok
                assert all(result.ok for result in await asyncio.gather(*pending[1:]))
            finally:
                release.set()
                await asyncio.gather(*pending, return_exceptions=True)

    asyncio.run(run())


def test_openapi_auth_and_no_request_parameters(voice):
    route = voice.app.openapi()["paths"][PATH]["post"]
    assert route["security"] == [{"SessionBearer": []}]
    assert "requestBody" not in route and "parameters" not in route
    assert set(route["responses"]) >= {"200", "401", "422", "429", "503"}


def test_voice_migration_is_additive_and_matches_model():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0005:0006", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql and "DROP TABLE" not in sql
    assert _table_elements(sql, "voice_session_rates") == _table_elements(
        _orm_sql("voice_session_rates"), "voice_session_rates"
    )
