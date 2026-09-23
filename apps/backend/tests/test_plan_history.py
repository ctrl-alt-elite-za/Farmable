"""Historical snapshots survive edits, not account erasure; no live provider calls."""

import io
from uuid import UUID, uuid4

import pytest
import test_production_planning as plans
from alembic import command
from alembic.config import Config
from farmable_backend.auth import PASSWORD_HASHER
from farmable_backend.models import AuthIdentity, PlanRevision, SavedPlan
from sqlalchemy import func, select
from test_farm_schema import _index_statements, _orm_sql, _table_elements

assistant = plans.assistant
planner = plans.planner


def history(planner, plan_id, **params):
    return planner.client.get(
        f"/farms/{planner.alice.farm}/planning/plans/{plan_id}/history",
        headers={"Authorization": planner.alice.auth},
        params=params,
    )


def test_confirmed_versions_are_preserved_and_paginated(planner):
    first = plans.confirmation(plans.preview(planner).json())
    assert plans.confirm(planner, first).status_code == 200
    original = history(planner, first["plan_id"]).json()["revisions"][0]
    assert original["origin"] == "planner_confirmation" and original["version"] == 1
    changed = plans.confirmation(
        plans.preview(planner, budget_cents=900_000).json(),
        plan_id=first["plan_id"],
        expected_version=1,
    )
    assert plans.confirm(planner, changed).json()["version"] == 2
    assert plans.confirm(planner, changed).json()["replayed"]
    assert plans.confirm(planner, first).status_code == 409
    page = history(planner, first["plan_id"], limit=1)
    assert page.headers["cache-control"] == "no-store"
    assert page.json()["next_before_version"] == 2
    assert page.json()["revisions"][0]["snapshot"]["plan"]["request"]["budget_cents"] == 900_000
    last = history(planner, first["plan_id"], limit=1, before_version=2).json()
    assert last["revisions"] == [original] and last["next_before_version"] is None
    assert len(history(planner, first["plan_id"]).json()["revisions"]) == 2
    assert history(planner, first["plan_id"], limit=21).status_code == 422
    assert history(planner, first["plan_id"], before_version=0).status_code == 422


def test_manual_edits_cannot_replace_or_forge_confirmation_history(planner):
    first = plans.confirmation(plans.preview(planner).json())
    plans.confirm(planner, first)
    original = history(planner, first["plan_id"]).json()["revisions"][0]
    root = f"/farms/{planner.alice.farm}/plans/{first['plan_id']}"
    headers = {"Authorization": planner.alice.auth}
    edited = planner.client.put(
        root,
        headers=headers,
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 1,
            "plan": {"origin": "planner_confirmation", "made_up": True},
        },
    )
    assert edited.status_code == 200, edited.text
    response = history(planner, first["plan_id"]).json()
    assert response["revisions"][0]["origin"] == "manual"
    assert response["revisions"][1] == original
    removed = planner.client.post(
        root + "/delete",
        headers=headers,
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 2,
        },
    )
    assert removed.status_code == 200, removed.text
    rows = history(planner, first["plan_id"]).json()["revisions"]
    assert [r["version"] for r in rows] == [3, 2, 1]
    assert rows[0]["snapshot"]["deleted_at"] is not None
    assert rows[-1] == original


def test_legacy_plan_baseline_is_saved_before_replacement(planner):
    identifier = uuid4()
    with planner.sessions.begin() as session:
        session.add(
            SavedPlan(
                id=identifier,
                owner_id=planner.alice.owner,
                farm_id=planner.alice.farm,
                section_id=planner.alice.section,
                plan={"legacy": True},
                version=7,
            )
        )
    assert history(planner, identifier).json()["revisions"] == []
    payload = plans.confirmation(
        plans.preview(planner).json(), plan_id=str(identifier), expected_version=7
    )
    assert plans.confirm(planner, payload).status_code == 200
    rows = history(planner, identifier).json()["revisions"]
    assert [r["version"] for r in rows] == [8, 7]
    assert rows[1]["origin"] == "baseline" and rows[1]["snapshot"]["plan"] == {"legacy": True}


def test_history_is_owner_scoped_and_erased_with_account(planner):
    payload = plans.confirmation(plans.preview(planner).json())
    plans.confirm(planner, payload)
    path = f"/farms/{planner.alice.farm}/planning/plans/{payload['plan_id']}/history"
    assert planner.client.get(path).status_code == 401
    assert planner.client.get(path, headers={"Authorization": planner.bob.auth}).status_code == 404
    wrong_farm = f"/farms/{planner.bob.farm}/planning/plans/{payload['plan_id']}/history"
    assert (
        planner.client.get(wrong_farm, headers={"Authorization": planner.bob.auth}).status_code
        == 404
    )
    assert history(planner, uuid4()).status_code == 404
    account = planner.client.app.state.account.service
    exported = account.export_document(planner.alice.auth)["plan_revisions"]
    assert len(exported) == 1 and exported[0]["plan_id"] == payload["plan_id"]
    assert account.export_document(planner.bob.auth)["plan_revisions"] == []
    with planner.sessions.begin() as session:
        session.get(AuthIdentity, planner.alice.owner).password_hash = PASSWORD_HASHER.hash(
            "fixture password"
        )
    account.delete_account(planner.alice.auth, "fixture password")
    with planner.sessions() as session:
        assert session.scalar(select(func.count()).select_from(PlanRevision)) == 0
    assert history(planner, payload["plan_id"]).status_code == 401


@pytest.mark.parametrize("updating", [False, True])
def test_failed_confirmation_does_not_archive_or_partially_save(planner, monkeypatch, updating):
    payload = plans.confirmation(plans.preview(planner).json())
    original_history = []
    if updating:
        assert plans.confirm(planner, payload).status_code == 200
        original_history = history(planner, payload["plan_id"]).json()["revisions"]
        payload = {**payload, "mutation_id": str(uuid4()), "expected_version": 1}
    original = plans.service.preserve

    def fail_after_snapshot(session, record, origin="baseline"):
        original(session, record, origin)
        session.flush()
        if origin == "planner_confirmation":
            raise RuntimeError("synthetic failure after snapshot")

    monkeypatch.setattr(plans.service, "preserve", fail_after_snapshot)
    assert plans.confirm(planner, payload).status_code == 500
    with planner.sessions() as session:
        record = session.get(SavedPlan, UUID(payload["plan_id"]))
        assert (record.version if record else 0) == (1 if updating else 0)
        assert session.scalar(select(func.count()).select_from(PlanRevision)) == int(updating)
    if updating:
        assert history(planner, payload["plan_id"]).json()["revisions"] == original_history


def test_manual_creation_retry_and_rejected_update_do_not_duplicate_history(planner):
    body = {
        "mutation_id": str(uuid4()),
        "id": str(uuid4()),
        "section_id": str(planner.alice.section),
        "plan": {"steps": []},
    }
    root = f"/farms/{planner.alice.farm}/plans"
    headers = {"Authorization": planner.alice.auth}
    assert planner.client.post(root, headers=headers, json=body).status_code == 200
    assert planner.client.post(root, headers=headers, json=body).status_code == 200
    rows = history(planner, body["id"]).json()["revisions"]
    assert len(rows) == 1 and rows[0]["origin"] == "manual"
    denied = planner.client.put(
        root + "/" + body["id"],
        headers=headers,
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 99,
            "plan": {"changed": True},
        },
    )
    assert denied.status_code == 409
    assert history(planner, body["id"]).json()["revisions"] == rows


def test_history_migration_is_additive_and_matches_model():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0012:0013", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql and "DROP" not in sql
    assert _table_elements(sql, "plan_revisions") == _table_elements(
        _orm_sql("plan_revisions"), "plan_revisions"
    )
    assert _index_statements(sql, "plan_revisions") == _index_statements(
        _orm_sql("plan_revisions"), "plan_revisions"
    )
