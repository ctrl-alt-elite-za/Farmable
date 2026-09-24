"""Synthetic Gemini Live contracts: no microphone, provider credentials or paid calls."""

import io
import json
from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from farmable_backend.assistant.live import LIVE_NOTICE_VERSION, LiveStore
from farmable_backend.auth import PASSWORD_HASHER
from farmable_backend.models import (
    AssistantLiveConsent,
    AssistantLiveSession,
    AuthIdentity,
    VoiceSessionRate,
)
from sqlalchemy import select
from test_assistant import assistant  # noqa: F401 -- shared fixture
from test_farm_schema import _index_statements, _orm_sql, _table_elements


@pytest.fixture
def live(assistant):  # noqa: F811 -- shared fixture
    adapter = assistant.client.app.state.services.gemini_live
    adapter.settings.gemini_live_enabled = True
    adapter.settings.gemini_live_model = "fixture-live-model"
    assistant.live = LiveStore(assistant.store, adapter)
    assistant.live_root = f"/assistant/conversations/{assistant.conversation}"
    assistant.headers = {"Authorization": assistant.alice.auth}
    return assistant


def consent(live):
    return live.client.put(
        live.live_root + "/live-consent",
        headers=live.headers,
        json={
            "notice_version": LIVE_NOTICE_VERSION,
            "model": "fixture-live-model",
        },
    )


def issue(live, identifier=None):
    return live.client.post(
        live.live_root + "/live-sessions",
        headers=live.headers,
        json={"id": str(identifier or uuid4())},
    )


def tool(live, identifier, **changes):
    return live.client.post(
        live.live_root + f"/live-sessions/{identifier}/tools",
        headers=live.headers,
        json={"id": "call-1", "name": "list_sections", "args": {}, **changes},
    )


def test_explicit_audio_consent_is_not_inferred_from_text_consent(live):
    view = live.client.get(live.live_root + "/live-consent", headers=live.headers)
    assert view.status_code == 200 and not view.json()["granted"]
    assert "cannot revoke" in view.json()["notice"]
    assert issue(live).status_code == 403
    assert not live.client.app.state.services.transport.calls
    assert consent(live).json()["granted"]
    identifier = uuid4()
    response = issue(live, identifier)
    assert response.status_code == 200, response.text
    body = response.json()
    assert body["id"] == str(identifier) and body["mode"] == "fake"
    assert body["credential"].startswith("auth_tokens/")
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["pragma"] == "no-cache"
    assert body["setup"]["model"] == "models/fixture-live-model"
    assert body["setup"]["inputAudioTranscription"] == {}
    assert (
        body["setup"]["realtimeInputConfig"]["activityHandling"] == "START_OF_ACTIVITY_INTERRUPTS"
    )
    assert {d["name"] for d in body["setup"]["tools"][0]["functionDeclarations"]} == {
        "list_sections",
        "get_crop_outlook",
        "preview_planting_plan",
    }
    assert issue(live, identifier).json()["error"]["code"] == "voice_session_not_replayable"
    assert issue(live).json()["error"]["code"] == "voice_session_in_progress"
    with live.sessions() as session:
        record = session.get(AssistantLiveSession, identifier)
        assert record.state == "active" and record.tool_count == 0
        assert len(session.get(VoiceSessionRate, live.alice.owner).hits) == 1
        assert "credential" not in AssistantLiveSession.__table__.columns


def test_read_tools_are_scoped_bounded_and_cannot_confirm(live):
    consent(live)
    identifier = issue(live).json()["id"]
    result = tool(live, identifier)
    assert result.status_code == 200
    assert [s["id"] for s in result.json()["response"]["sections"]] == [str(live.alice.section)]
    assert tool(live, identifier, name="confirm_planting_plan").status_code == 422
    assert tool(live, identifier, args={"owner_id": str(live.bob.owner)}).json()["response"] == {
        "error": "invalid_tool_arguments"
    }
    assert tool(live, identifier, args={"large": "x" * 4096}).status_code == 422
    denied = tool(
        live,
        identifier,
        name="get_crop_outlook",
        args={
            "section_id": str(live.bob.section),
            "crop": "cabbage",
            "plant_month": 10,
        },
    )
    assert denied.json()["response"] == {"error": "not_found"}
    with live.sessions.begin() as session:
        session.get(AssistantLiveSession, UUID(identifier)).tool_count = 32
    assert tool(live, identifier).json()["error"]["code"] == "voice_tool_limit"


def test_withdrawal_regrant_and_interrupt_never_revive_old_sessions(live):
    consent(live)
    identifier = issue(live).json()["id"]
    assert (
        live.client.delete(live.live_root + "/live-consent", headers=live.headers).status_code
        == 200
    )
    assert tool(live, identifier).status_code == 403
    assert consent(live).status_code == 200
    assert tool(live, identifier).json()["error"]["code"] == "voice_session_ended"
    path = live.live_root + f"/live-sessions/{identifier}"
    status = live.client.get(path, headers=live.headers).json()
    assert status["state"] == "interrupted" and status["disconnect_required"]
    new_id = issue(live).json()["id"]
    path = live.live_root + f"/live-sessions/{new_id}/interrupt"
    first = live.client.post(path, headers=live.headers)
    assert first.status_code == 200 and first.json()["disconnect_required"]
    assert live.client.post(path, headers=live.headers).json() == first.json()
    assert tool(live, new_id).status_code == 409


@pytest.mark.parametrize("action", ["withdraw", "interrupt", "change_model", "disable", "delete"])
def test_late_credential_never_released_after_authority_changes(live, monkeypatch, action):
    consent(live)
    adapter = live.client.app.state.services.gemini_live
    original = adapter.issue
    identifier = uuid4()

    async def delayed(**kwargs):
        result = await original(**kwargs)
        if action == "withdraw":
            live.live.consent(live.alice.auth, live.conversation, withdraw=True)
            # Even reconsenting before the provider returns cannot revive issuance.
            from farmable_backend.assistant.live import LiveConsentGrant

            live.live.consent(
                live.alice.auth,
                live.conversation,
                LiveConsentGrant(notice_version=LIVE_NOTICE_VERSION, model="fixture-live-model"),
            )
        elif action == "interrupt":
            live.live.state(live.alice.auth, live.conversation, identifier, interrupt=True)
        elif action == "change_model":
            adapter.settings.gemini_live_model = "changed-model"
        elif action == "disable":
            adapter.settings.gemini_live_enabled = False
        else:
            with live.sessions.begin() as session:
                session.delete(session.get(AuthIdentity, live.alice.owner))
        return result

    monkeypatch.setattr(adapter, "issue", delayed)
    response = issue(live, identifier)
    assert response.status_code in (401, 403, 409)
    assert "credential" not in response.text and "auth_tokens/" not in response.text


def test_expiry_auth_scope_and_model_change_are_checked_per_tool(live):
    consent(live)
    identifier = issue(live).json()["id"]
    path = live.live_root + f"/live-sessions/{identifier}"
    assert live.client.get(path).status_code == 401
    assert live.client.get(path, headers={"Authorization": live.bob.auth}).status_code == 404
    adapter = live.client.app.state.services.gemini_live
    adapter.settings.gemini_live_model = "changed-model"
    assert tool(live, identifier).status_code == 403
    adapter.settings.gemini_live_model = "fixture-live-model"
    with live.sessions.begin() as session:
        session.get(AssistantLiveSession, UUID(identifier)).expires_at = datetime.now(
            UTC
        ) - timedelta(seconds=1)
    assert tool(live, identifier).json()["error"]["code"] == "voice_session_expired"
    assert live.client.get(path, headers=live.headers).json()["disconnect_required"]


def test_failed_mints_consume_shared_quota_without_retry(live):
    consent(live)
    transport = live.client.app.state.services.transport
    transport.modes["gemini"] = "error"
    for _ in range(3):
        assert issue(live).status_code == 503
    assert issue(live).status_code == 429
    assert live.client.post("/voice/live-session", headers=live.headers).status_code == 429
    assert transport.calls["gemini"] == 3
    with live.sessions() as session:
        assert all(r.state == "failed" for r in session.scalars(select(AssistantLiveSession)))


@pytest.mark.parametrize("withdraw", [False, True])
def test_tool_result_is_withheld_when_authority_changes_during_read(live, monkeypatch, withdraw):
    from farmable_backend.assistant import live as module

    consent(live)
    identifier = issue(live).json()["id"]
    original = module.execute

    def delayed(*args):
        result = original(*args)
        if withdraw:
            live.live.consent(live.alice.auth, live.conversation, withdraw=True)
        else:
            live.live.state(live.alice.auth, live.conversation, UUID(identifier), interrupt=True)
        return result

    monkeypatch.setattr(module, "execute", delayed)
    response = tool(live, identifier)
    assert response.status_code == (403 if withdraw else 409)
    assert str(live.alice.section) not in response.text


def test_caller_cannot_override_setup_or_supply_extra_parameters(live):
    consent(live)
    path = live.live_root + "/live-sessions"
    for extra in ({"setup": {}}, {"model": "other"}, {"tools": []}):
        response = live.client.post(path, headers=live.headers, json={"id": str(uuid4()), **extra})
        assert response.status_code == 422
    response = live.client.post(
        path + "?model=other", headers=live.headers, json={"id": str(uuid4())}
    )
    assert response.status_code == 422
    assert not live.client.app.state.services.transport.calls


def test_export_and_deletion_include_only_owned_metadata(live):
    consent(live)
    identifier = issue(live).json()["id"]
    account = live.client.app.state.account.service
    document = account.export_document(live.alice.auth)
    assert document["assistant_live_sessions"][0]["id"] == identifier
    assert document["assistant_live_consents"][0]["model"] == "fixture-live-model"
    assert "auth_tokens/" not in json.dumps(document)
    assert account.export_document(live.bob.auth)["assistant_live_sessions"] == []
    with live.sessions.begin() as session:
        session.get(AuthIdentity, live.alice.owner).password_hash = PASSWORD_HASHER.hash(
            "fixture password"
        )
    account.delete_account(live.alice.auth, "fixture password")
    with live.sessions() as session:
        assert session.get(AssistantLiveSession, UUID(identifier)) is None
        assert session.get(AssistantLiveConsent, live.conversation) is None


def test_live_migration_matches_models_without_implicit_consent():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0013:0014", sql=True)
    sql = output.getvalue()
    assert "INSERT INTO assistant_live" not in sql and "DROP TABLE" not in sql
    for name in ("assistant_live_consents", "assistant_live_sessions"):
        assert _table_elements(sql, name) == _table_elements(_orm_sql(name), name)
        assert _index_statements(sql, name) == _index_statements(_orm_sql(name), name)
