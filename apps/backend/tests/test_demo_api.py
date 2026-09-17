import json
from concurrent.futures import ThreadPoolExecutor
from decimal import Decimal
from tempfile import TemporaryDirectory
from uuid import UUID, uuid4

import pytest
from farmable_backend.demo_api import rehearse
from farmable_backend.demo_api.app import create_demo_app
from farmable_backend.demo_api.geometry import example_rectangle
from farmable_backend.demo_api.schemas import Boundary, Dashboard, DemoSession, SavedPlan
from farmable_backend.demo_api.storage import DemoState, DemoStore, initialize_storage
from fastapi.testclient import TestClient
from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session


@pytest.fixture
def db_path(tmp_path):
    path = tmp_path / "prototype.sqlite3"
    initialize_storage(path)
    return path


@pytest.fixture
def client(db_path):
    with TestClient(create_demo_app(db_path)) as test_client:
        yield test_client


def start(client):
    response = client.post("/demo/sessions", json={})
    assert response.status_code == 201
    session = response.json()
    assert DemoSession.model_validate(session)
    return session, {"Authorization": "Bearer " + session["access_token"]}


def write_headers(auth, key=None, **extra):
    return {**auth, "Idempotency-Key": key or str(uuid4()), **extra}


def available(session):
    return next(
        section for section in session["dashboard"]["sections"] if section["current_crop"] is None
    )


def inputs(**changes):
    return {"planting_date": "2026-09-18", "budget_cents": 300_000, **changes}


def proposed(client, section_id, auth, **changes):
    response = client.post(
        f"/demo/sections/{section_id}/plans", json=inputs(**changes), headers=write_headers(auth)
    )
    assert response.status_code == 201
    assert SavedPlan.model_validate(response.json())
    return response.json()


def test_full_contextual_journey_replans_approves_reopens_and_restarts(client, db_path):
    session, auth = start(client)
    section = available(session)
    assert section["area_m2"] == "400.00"
    baseline = proposed(client, section["id"], auth)
    changed = client.post(
        f"/demo/plans/{baseline['id']}/constraints",
        json=inputs(budget_cents=210_000, min_crop_shares=[{"crop": "cabbage", "percent": 50}]),
        headers=write_headers(auth),
    )
    assert changed.status_code == 201
    revised = changed.json()
    assert revised["parent_plan_id"] == baseline["id"]
    assert revised["version"] == 2
    assert revised["result"]["plans"][0]["blocks"] == ["cabbage", "cabbage", "spinach", None]
    assert revised["result"]["plans"][0]["total_cost_cents"] == 210_000
    assert revised["status"] == "proposed"
    assert client.get("/demo/farm", headers=auth).json()["approved_plans"] == []
    approval = client.post(
        f"/demo/plans/{revised['id']}/approve", json={}, headers=write_headers(auth)
    )
    assert approval.status_code == 200
    assert approval.json()["status"] == "approved"
    board = client.get("/demo/farm", headers=auth).json()
    assert len(board["approved_plans"]) == 1
    assert board["approved_plans"][0]["id"] == revised["id"]
    assert (
        next(s for s in board["sections"] if s["id"] == section["id"])["planned_plan_id"]
        == revised["id"]
    )
    assert client.get(f"/demo/plans/{baseline['id']}", headers=auth).json()["status"] == "proposed"
    # A new app/store connection to the same local DB simulates a server restart.
    with TestClient(create_demo_app(db_path)) as restarted:
        assert restarted.get(f"/demo/plans/{revised['id']}", headers=auth).json() == approval.json()
        assert restarted.get("/demo/farm", headers=auth).json() == board


def test_seed_is_fictional_and_dashboard_has_honest_empty_states(client):
    session, auth = start(client)
    board = client.get("/demo/farm", headers=auth).json()
    assert board == session["dashboard"]
    assert board["name"] == "Hammanskraal example farm"
    assert board["total_section_area_m2"] == "480.00"
    assert board["analytics"] is None
    assert board["approved_plans"] == []
    for section in board["sections"]:
        assert section["health_assessment"] is None
        assert section["soil_information"] == "unknown"
    assert Dashboard.model_validate(board)


def test_preview_uses_owned_section_area_and_does_not_save(client):
    session, auth = start(client)
    section = available(session)
    route = f"/demo/sections/{section['id']}/preview"
    first = client.post(route, json=inputs(), headers=auth)
    assert first.status_code == 200
    assert first.json()["request"]["area_m2"] == "400.00"
    assert first.json()["request"]["section_id"] == section["id"]
    assert client.post(route, json=inputs(area_m2="1000000"), headers=auth).status_code == 422
    assert client.post(route, json=inputs(section_id=str(uuid4())), headers=auth).status_code == 422
    assert first.json() == client.post(route, json=inputs(), headers=auth).json()
    assert client.get("/demo/farm", headers=auth).json()["approved_plans"] == []


@pytest.mark.parametrize(
    "changes,reason",
    [
        (
            {"budget_cents": 100_000, "min_crop_shares": [{"crop": "cabbage", "percent": 50}]},
            "minimum_share_exceeds_budget",
        ),
        ({"planting_date": "2026-10-01"}, "unsupported_date"),
    ],
)
def test_infeasible_preview_is_explicit_and_cannot_be_saved(client, changes, reason):
    session, auth = start(client)
    section = available(session)
    preview = client.post(
        f"/demo/sections/{section['id']}/preview", json=inputs(**changes), headers=auth
    )
    assert preview.status_code == 200
    assert preview.json()["feasible"] is False
    assert preview.json()["reason"]["code"] == reason
    assert preview.json()["plans"] == []
    save = client.post(
        f"/demo/sections/{section['id']}/plans", json=inputs(**changes), headers=write_headers(auth)
    )
    assert save.status_code == 422
    assert save.json()["error"]["code"] == reason
    assert client.get("/demo/farm", headers=auth).json()["approved_plans"] == []


def test_section_crud_is_idempotent_and_updates_area_with_optimistic_revision(client):
    _, auth = start(client)
    headers = write_headers(auth)
    payload = {"name": "New section", "area_m2": "200"}
    first = client.post("/demo/sections", json=payload, headers=headers)
    again = client.post("/demo/sections", json=payload, headers=headers)
    assert first.status_code == again.status_code == 201
    assert first.json() == again.json()
    section = first.json()
    assert len(client.get("/demo/farm", headers=auth).json()["sections"]) == 4
    conflict = client.post("/demo/sections", json={**payload, "area_m2": "201"}, headers=headers)
    assert conflict.status_code == 409
    assert conflict.json()["error"]["code"] == "idempotency_conflict"
    update = client.put(
        f"/demo/sections/{section['id']}",
        json={"name": "Smaller section", "area_m2": "100"},
        headers=write_headers(auth, **{"Section-Revision": "1"}),
    )
    assert update.status_code == 200
    assert update.json()["revision"] == 2
    assert Decimal(update.json()["area_m2"]) == 100
    stale = client.put(
        f"/demo/sections/{section['id']}",
        json=payload,
        headers=write_headers(auth, **{"Section-Revision": "1"}),
    )
    assert stale.status_code == 409
    delete_headers = write_headers(auth)
    for _ in range(2):
        assert (
            client.delete(f"/demo/sections/{section['id']}", headers=delete_headers).status_code
            == 204
        )
    assert client.get(f"/demo/sections/{section['id']}", headers=auth).status_code == 404


def test_boundary_area_is_calculated_server_side_and_moving_a_corner_changes_it(client):
    _, auth = start(client)
    boundary = {"type": "Polygon", "coordinates": [example_rectangle(10, 20)]}
    response = client.post(
        "/demo/sections",
        json={"name": "Drawn section", "boundary": boundary},
        headers=write_headers(auth),
    )
    assert response.status_code == 201
    section = response.json()
    assert Decimal(section["area_m2"]) == 200
    assert section["area_source"] == "boundary_estimate"
    update = client.put(
        f"/demo/sections/{section['id']}",
        json={"name": "Drawn section", "boundary": {"coordinates": [example_rectangle(20, 20)]}},
        headers=write_headers(auth, **{"Section-Revision": "1"}),
    )
    assert Decimal(update.json()["area_m2"]) == 400
    assert (
        client.post(
            "/demo/sections",
            json={"name": "Conflicting area", "boundary": boundary, "area_m2": "1000"},
            headers=write_headers(auth),
        ).status_code
        == 422
    )


def test_editing_land_invalidates_active_link_and_old_proposal_cannot_be_approved(client):
    session, auth = start(client)
    section = available(session)
    saved = proposed(client, section["id"], auth)
    assert (
        client.post(
            f"/demo/plans/{saved['id']}/approve", json={}, headers=write_headers(auth)
        ).status_code
        == 200
    )
    changed = client.put(
        f"/demo/sections/{section['id']}",
        json={"name": section["name"], "area_m2": "200"},
        headers=write_headers(auth, **{"Section-Revision": "1"}),
    )
    assert changed.status_code == 200
    assert changed.json()["planned_plan_id"] is None
    blocked = client.post(
        f"/demo/plans/{saved['id']}/approve", json={}, headers=write_headers(auth)
    )
    assert blocked.status_code == 409
    assert blocked.json()["error"]["code"] == "stale_section"
    assert client.get("/demo/farm", headers=auth).json()["approved_plans"] == []


def test_other_sessions_cannot_read_modify_delete_replan_or_approve_resources(client):
    first, first_auth = start(client)
    section = available(first)
    saved = proposed(client, section["id"], first_auth)
    _, other_auth = start(client)
    calls = [
        ("get", f"/demo/sections/{section['id']}", None),
        ("put", f"/demo/sections/{section['id']}", {"name": "Attack", "area_m2": "1"}),
        ("delete", f"/demo/sections/{section['id']}", None),
        ("post", f"/demo/sections/{section['id']}/preview", inputs()),
        ("post", f"/demo/sections/{section['id']}/plans", inputs()),
        ("get", f"/demo/plans/{saved['id']}", None),
        ("post", f"/demo/plans/{saved['id']}/constraints", inputs()),
        ("post", f"/demo/plans/{saved['id']}/approve", {}),
    ]
    for method, route, payload in calls:
        headers = write_headers(other_auth, **{"Section-Revision": "1"})
        kwargs = {"headers": headers}
        if payload is not None:
            kwargs["json"] = payload
        assert client.request(method, route, **kwargs).status_code == 404


def test_reset_is_private_repeatable_and_invalidates_old_sections_plans(client):
    first, auth = start(client)
    other, other_auth = start(client)
    saved = proposed(client, available(first)["id"], auth)
    headers = write_headers(auth)
    reset = client.post("/demo/reset", json={}, headers=headers)
    assert reset.status_code == 200
    assert reset.json()["farm_id"] == first["dashboard"]["farm_id"]
    assert client.post("/demo/reset", json={}, headers=headers).json() == reset.json()
    assert client.get(f"/demo/plans/{saved['id']}", headers=auth).status_code == 404
    assert client.get("/demo/farm", headers=other_auth).json() == other["dashboard"]
    assert client.get("/demo/farm", headers=auth).json() == reset.json()


def test_save_and_approve_retries_do_not_duplicate_plans(client):
    session, auth = start(client)
    route = f"/demo/sections/{available(session)['id']}/plans"
    headers = write_headers(auth)
    first = client.post(route, json=inputs(), headers=headers).json()
    assert client.post(route, json=inputs(), headers=headers).json() == first
    assert client.post(route, json=inputs(budget_cents=210_000), headers=headers).status_code == 409
    approval_headers = write_headers(auth)
    approval = client.post(f"/demo/plans/{first['id']}/approve", json={}, headers=approval_headers)
    assert (
        client.post(f"/demo/plans/{first['id']}/approve", json={}, headers=approval_headers).json()
        == approval.json()
    )
    assert len(client.get("/demo/farm", headers=auth).json()["approved_plans"]) == 1


def test_deleting_section_removes_its_snapshots_without_affecting_other_sections(client):
    session, auth = start(client)
    section = available(session)
    saved = proposed(client, section["id"], auth)
    assert (
        client.delete(f"/demo/sections/{section['id']}", headers=write_headers(auth)).status_code
        == 204
    )
    assert client.get(f"/demo/plans/{saved['id']}", headers=auth).status_code == 404
    assert len(client.get("/demo/farm", headers=auth).json()["sections"]) == 2


@pytest.mark.parametrize("token", [None, "invalid", "x" * 43, "x" * 10000])
def test_missing_invalid_or_unknown_capability_cannot_read_state(client, token):
    headers = {} if token is None else {"Authorization": "Bearer " + token}
    response = client.get("/demo/farm", headers=headers)
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_demo_session"
    assert response.headers["x-request-id"]


def test_capabilities_are_not_stored_in_plaintext(db_path):
    store = DemoStore(db_path)
    try:
        token, farm = store.create()
        with Session(store.engine) as session:
            row = session.scalar(select(DemoState))
            assert row.id == str(farm.id)
            assert row.token_hash != token
            assert token not in json.dumps(row.payload)
    finally:
        store.close()


def test_concurrent_section_creates_preserve_all_updates(client):
    _, auth = start(client)

    def create(index):
        return client.post(
            "/demo/sections",
            json={"name": f"Section {index}", "area_m2": "10"},
            headers=write_headers(auth),
        )

    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(create, range(8)))
    assert all(response.status_code == 201 for response in responses)
    assert len(client.get("/demo/farm", headers=auth).json()["sections"]) == 11


def test_all_inputs_are_bounded_and_unknown_fields_rejected(client):
    session, auth = start(client)
    for payload in [
        {"name": "", "area_m2": "100"},
        {"name": " " * 10, "area_m2": "100"},
        {"name": "x" * 61, "area_m2": "100"},
        {"name": "A", "area_m2": "0"},
        {"name": "A", "area_m2": "NaN"},
        {"name": "A", "area_m2": "1", "farm_id": str(uuid4())},
        {"name": "A"},
    ]:
        assert (
            client.post("/demo/sections", json=payload, headers=write_headers(auth)).status_code
            == 422
        )
    assert client.post("/demo/sessions", json={"name": "not permitted"}).status_code == 422
    assert (
        client.post(
            f"/demo/sections/{available(session)['id']}/plans",
            json=inputs(selection_index=9),
            headers=write_headers(auth),
        ).status_code
        == 422
    )
    assert (
        client.post("/demo/sections", json={"name": "A", "area_m2": "1"}, headers=auth).status_code
        == 422
    )


def test_cors_preflight_supports_edit_revision_and_disallows_unconfigured_origin(client):
    headers = {
        "Origin": "http://localhost:5173",
        "Access-Control-Request-Method": "PUT",
        "Access-Control-Request-Headers": (
            "Authorization,Content-Type,Idempotency-Key,Section-Revision"
        ),
    }
    response = client.options("/demo/sections/example", headers=headers)
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == headers["Origin"]
    assert (
        client.options(
            "/demo/sections/example", headers={**headers, "Origin": "https://not-allowed.example"}
        ).status_code
        == 400
    )
    with pytest.raises(ValueError, match="explicit"):
        create_demo_app(origins=("*",))


def test_body_limit_and_private_responses_have_safe_headers(client):
    session, auth = start(client)
    response = client.get("/demo/farm", headers=auth)
    assert response.headers["cache-control"] == "no-store"
    assert UUID(response.headers["x-request-id"])
    oversized = client.post(
        "/demo/sections",
        content=b"x" * 65537,
        headers=write_headers(auth, **{"Content-Type": "application/json"}),
    )
    assert oversized.status_code == 413
    assert oversized.json()["error"]["code"] == "request_too_large"
    assert UUID(oversized.headers["x-request-id"])


def test_storage_failure_is_not_success_and_does_not_expose_internal_details(client, monkeypatch):
    session, auth = start(client)

    def fail(*args):
        raise RuntimeError("sensitive storage path and password")

    monkeypatch.setattr(DemoStore, "update", fail)
    response = client.post(
        f"/demo/sections/{available(session)['id']}/plans",
        json=inputs(),
        headers=write_headers(auth),
    )
    assert response.status_code == 500
    assert response.json()["error"]["code"] == "internal_error"
    assert "sensitive" not in response.text
    assert UUID(response.headers["x-request-id"])
    assert response.headers["cache-control"] == "no-store"


def test_replaying_old_approval_after_edit_does_not_report_fresh_approval(client):
    session, auth = start(client)
    section = available(session)
    saved = proposed(client, section["id"], auth)
    headers = write_headers(auth)
    route = f"/demo/plans/{saved['id']}/approve"
    assert client.post(route, json={}, headers=headers).status_code == 200
    changed = client.put(
        f"/demo/sections/{section['id']}",
        json={"name": section["name"], "area_m2": "200"},
        headers=write_headers(auth, **{"Section-Revision": "1"}),
    )
    assert changed.status_code == 200
    assert client.post(route, json={}, headers=headers).status_code == 409
    assert client.get("/demo/farm", headers=auth).json()["approved_plans"] == []


def test_concurrent_retries_create_only_one_section(client):
    _, auth = start(client)
    headers = write_headers(auth)

    def create(_):
        return client.post(
            "/demo/sections", json={"name": "One section", "area_m2": "10"}, headers=headers
        )

    with ThreadPoolExecutor(max_workers=4) as pool:
        responses = list(pool.map(create, range(4)))
    assert all(response.status_code == 201 for response in responses)
    assert len({response.json()["id"] for response in responses}) == 1
    assert len(client.get("/demo/farm", headers=auth).json()["sections"]) == 4


def test_session_limit_is_enforced_without_provider_calls(client):
    for _ in range(32):
        assert client.post("/demo/sessions", json={}).status_code == 201
    response = client.post("/demo/sessions", json={})
    assert response.status_code == 429
    assert response.json()["error"]["code"] == "demo_session_limit"


def test_section_limit_does_not_write_an_extra_section(client):
    _, auth = start(client)
    for index in range(17):
        response = client.post(
            "/demo/sections",
            json={"name": f"Extra {index}", "area_m2": "10"},
            headers=write_headers(auth),
        )
        assert response.status_code == 201
    blocked = client.post(
        "/demo/sections", json={"name": "Too many", "area_m2": "10"}, headers=write_headers(auth)
    )
    assert blocked.status_code == 409
    assert len(client.get("/demo/farm", headers=auth).json()["sections"]) == 20


def test_plan_snapshot_limit_does_not_write_a_partial_proposal(client):
    session, auth = start(client)
    route = f"/demo/sections/{available(session)['id']}/plans"
    for _ in range(40):
        assert client.post(route, json=inputs(), headers=write_headers(auth)).status_code == 201
    response = client.post(route, json=inputs(), headers=write_headers(auth))
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "demo_plan_limit"


def test_successful_operation_limit_can_be_reset(client):
    session, auth = start(client)
    section = available(session)
    saved = proposed(client, section["id"], auth)
    route = f"/demo/plans/{saved['id']}/approve"
    for _ in range(99):
        assert client.post(route, json={}, headers=write_headers(auth)).status_code == 200
    blocked = client.post(route, json={}, headers=write_headers(auth))
    assert blocked.status_code == 409
    assert blocked.json()["error"]["code"] == "demo_operation_limit"
    # This assertion records whether the documented reset escape hatch actually works.
    assert client.post("/demo/reset", json={}, headers=write_headers(auth)).status_code == 200


@pytest.mark.parametrize(
    "ring",
    [
        ((0, 0), (0.001, 0), (0, 0.001), (0.001, 0.001), (0, 0)),
        ((0, 0), (0.001, 0), (0.002, 0), (0, 0)),
        ((0, 0), (0.001, 0), (0, 0.001), (0.001, 0)),
        ((0, 0), (1, 0), (0, 1), (0, 0)),
        ((0, 90), (0.001, 90), (0, 89), (0, 90)),
        ((float("nan"), 0), (0.001, 0), (0, 0.001), (float("nan"), 0)),
    ],
)
def test_invalid_boundaries_are_rejected(ring):
    with pytest.raises(ValidationError):
        Boundary.model_validate({"coordinates": [ring]})


def test_storage_initialization_is_idempotent_and_does_not_clear_existing_state(db_path):
    store = DemoStore(db_path)
    try:
        token, farm = store.create()
        initialize_storage(db_path)
        assert store.read(token) == farm
    finally:
        store.close()


def test_openapi_has_provisional_models_errors_and_capability_security():
    schema = create_demo_app().openapi()
    assert schema["info"]["version"].endswith("prototype")
    assert schema["paths"]["/demo/farm"]["get"]["security"]
    assert "HTTPValidationError" not in schema["components"]["schemas"]
    assert schema["paths"]["/demo/sections"]["post"]["responses"]["422"]["content"][
        "application/json"
    ]["schema"]["$ref"].endswith("/ErrorResponse")


def test_real_http_rehearsal_closes_storage_before_reporting_pass(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(
        rehearse, "TemporaryDirectory", lambda **kwargs: TemporaryDirectory(dir=tmp_path, **kwargs)
    )
    rehearse.main()
    report = json.loads(capsys.readouterr().out)
    assert len(report) == 3
    assert all(row["result"] == "pass" for row in report)
    assert list(tmp_path.iterdir()) == []


def test_rehearsal_failure_stops_server_and_never_reports_pass(monkeypatch, tmp_path, capsys):
    monkeypatch.setattr(
        rehearse, "TemporaryDirectory", lambda **kwargs: TemporaryDirectory(dir=tmp_path, **kwargs)
    )

    def fail(client):
        raise RuntimeError("Intentional synthetic rehearsal failure")

    monkeypatch.setattr(rehearse, "journey", fail)
    with pytest.raises(RuntimeError, match="Intentional synthetic"):
        rehearse.main()
    assert capsys.readouterr().out == ""
    assert list(tmp_path.iterdir()) == []
