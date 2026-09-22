"""REST and sync contract for #11: owner scope, idempotency and change polling."""

from uuid import UUID, uuid4

import pytest
from farmable_backend.models import FarmTask, SyncChange
from farmable_backend.records_schemas import (
    FinancialCreate,
    FinancialUpdate,
    MediaCreate,
    MediaUpdate,
    ObservationUpdate,
    PlanCreate,
    PlantingCreate,
    PlantingUpdate,
    PlanUpdate,
    RecordDelete,
    SectionCreate,
    SectionUpdate,
    TaskCreate,
    TaskUpdate,
)
from sqlalchemy import func, select
from test_records_api import observation_payload

pytest_plugins = ("test_records_api",)

CREATE_FIELDS = {
    "sections": lambda ids: {"name": "North block", "area_m2": "1200.00"},
    "plantings": lambda ids: {
        "section_id": str(ids.section),
        "crop": "cabbage",
        "planted_on": "2026-08-01",
    },
    "tasks": lambda ids: {
        "section_id": str(ids.section),
        "title": "Weed the beds",
        "due_date": "2026-10-01",
        "status": "pending",
        "expected_cost_cents": 1500,
    },
    "financials": lambda ids: {
        "section_id": str(ids.section),
        "type": "expense",
        "category": "seed",
        "amount_cents": 4200,
        "date": "2026-09-01",
    },
    "plans": lambda ids: {
        "section_id": str(ids.section),
        "status": "saved",
        "plan": {"steps": []},
    },
    "media": lambda ids: {
        "section_id": str(ids.section),
        "local_id": "device-photo-1",
        "media_type": "image/png",
    },
}

UPDATE_FIELDS = {
    "sections": lambda ids: {"name": "South block", "area_m2": "1300.00"},
    "plantings": lambda ids: {"crop": "tomato", "planted_on": "2026-08-02"},
    "tasks": lambda ids: {"title": "Weed again", "due_date": "2026-10-02", "status": "done"},
    "financials": lambda ids: {
        "type": "income",
        "category": "sale",
        "amount_cents": 9900,
        "date": "2026-09-02",
    },
    "plans": lambda ids: {"status": "approved", "plan": {"steps": ["irrigate"]}},
    "media": lambda ids: {"section_id": str(ids.section), "media_type": "image/jpeg"},
}

RESOURCES = tuple(CREATE_FIELDS)
READABLE = ("plantings", "tasks", "financials", "plans", "media")

EXAMPLE_MODELS = (
    FinancialCreate,
    FinancialUpdate,
    MediaCreate,
    MediaUpdate,
    ObservationUpdate,
    PlanCreate,
    PlantingCreate,
    PlantingUpdate,
    PlanUpdate,
    RecordDelete,
    SectionCreate,
    SectionUpdate,
    TaskCreate,
    TaskUpdate,
)


def create_body(records, resource, record_id=None):
    return {
        "mutation_id": str(uuid4()),
        "id": record_id or str(uuid4()),
        **CREATE_FIELDS[resource](records.ids),
    }


def update_body(records, resource, expected_version=1):
    return {
        "mutation_id": str(uuid4()),
        "expected_version": expected_version,
        **UPDATE_FIELDS[resource](records.ids),
    }


@pytest.mark.parametrize("resource", RESOURCES)
def test_authenticated_crud_round_trip(records, resource):
    base = f"/farms/{records.ids.farm}/{resource}"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, resource, record_id))
    assert created.status_code == 200, created.text
    body = created.json()
    assert body["entity_id"] == record_id
    assert body["owner_id"] == str(records.ids.owner)
    assert body["farm_id"] == str(records.ids.farm)
    assert body["version"] == 1
    assert body["record"]["id"] == record_id
    updated = records.client.put(f"{base}/{record_id}", json=update_body(records, resource))
    assert updated.status_code == 200, updated.text
    assert updated.json()["version"] == 2
    removed = records.client.post(f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4())})
    assert removed.status_code == 200, removed.text
    assert removed.json()["version"] == 3


@pytest.mark.parametrize("resource", READABLE)
def test_list_and_get_expose_active_records_only(records, resource):
    base = f"/farms/{records.ids.farm}/{resource}"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, resource, record_id))
    assert created.status_code == 200, created.text
    assert records.client.get(f"{base}/{record_id}").json()["id"] == record_id
    assert [item["id"] for item in records.client.get(base).json()["items"]] == [record_id]
    removed = records.client.post(f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4())})
    assert removed.status_code == 200, removed.text
    assert records.client.get(base).json()["items"] == []
    assert records.client.get(f"{base}/{record_id}").status_code == 404


def test_list_filters_by_owned_section(records):
    base = f"/farms/{records.ids.farm}/tasks"
    created = records.client.post(base, json=create_body(records, "tasks"))
    assert created.status_code == 200, created.text
    owned = records.client.get(f"{base}?section_id={records.ids.section}")
    assert len(owned.json()["items"]) == 1
    assert records.client.get(f"{base}?section_id={records.ids.second_section}").status_code == 404


def test_replaying_a_mutation_creates_one_logical_record(records):
    base = f"/farms/{records.ids.farm}/tasks"
    payload = create_body(records, "tasks")
    first = records.client.post(base, json=payload)
    assert first.status_code == 200, first.text
    replay = records.client.post(base, json=payload)
    assert replay.status_code == 200, replay.text
    assert replay.json() == first.json()
    assert len(records.client.get(base).json()["items"]) == 1
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(FarmTask)) == 1
        assert session.scalar(select(func.count()).select_from(SyncChange)) == 1


def test_a_real_constraint_violation_is_reported_as_record_conflict(records):
    base = f"/farms/{records.ids.farm}/plantings"
    first = records.client.post(base, json=create_body(records, "plantings"))
    assert first.status_code == 200, first.text
    second_payload = create_body(records, "plantings")
    second = records.client.post(base, json=second_payload)
    assert second.status_code == 409
    assert second.json()["error"]["code"] == "record_conflict"


def test_a_cross_owner_primary_key_collision_is_reported_as_record_conflict(records):
    from datetime import date

    from farmable_backend.models import FarmTask

    base = f"/farms/{records.ids.farm}/tasks"
    record_id = uuid4()
    with records.sessions.begin() as session:
        session.add(
            FarmTask(
                id=record_id,
                farm_id=records.ids.foreign,
                owner_id=records.ids.other,
                section_id=records.ids.foreign_section,
                title="Not yours",
                due_date=date(2026, 10, 1),
            )
        )
    colliding = create_body(records, "tasks", str(record_id))
    response = records.client.post(base, json=colliding)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "record_conflict"


def test_delete_enforces_optimistic_concurrency(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    stale = records.client.post(
        f"{base}/{record_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": 2},
    )
    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "revision_conflict"
    assert records.client.get(f"{base}/{record_id}").status_code == 200


def test_replaying_an_update_mutation_does_not_double_apply(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    payload = update_body(records, "tasks")
    first = records.client.put(f"{base}/{record_id}", json=payload)
    assert first.status_code == 200, first.text
    assert first.json()["version"] == 2
    replay = records.client.put(f"{base}/{record_id}", json=payload)
    assert replay.status_code == 200, replay.text
    assert replay.json() == first.json()
    assert records.client.get(f"{base}/{record_id}").json()["version"] == 2
    with records.sessions() as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(SyncChange)
                .where(SyncChange.record_id == UUID(record_id), SyncChange.operation == "update")
            )
            == 1
        )


def test_replaying_a_delete_mutation_does_not_double_apply(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    delete_payload = {"mutation_id": str(uuid4())}
    first = records.client.post(f"{base}/{record_id}/delete", json=delete_payload)
    assert first.status_code == 200, first.text
    replay = records.client.post(f"{base}/{record_id}/delete", json=delete_payload)
    assert replay.status_code == 200, replay.text
    assert replay.json() == first.json()
    with records.sessions() as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(SyncChange)
                .where(SyncChange.record_id == UUID(record_id), SyncChange.operation == "delete")
            )
            == 1
        )


def test_mutation_id_reuse_with_different_work_conflicts(records):
    base = f"/farms/{records.ids.farm}/tasks"
    payload = create_body(records, "tasks")
    assert records.client.post(base, json=payload).status_code == 200
    changed = dict(payload, title="Different work")
    response = records.client.post(base, json=changed)
    assert response.status_code == 409
    assert response.json()["error"]["code"] == "mutation_conflict"


def test_stale_revision_returns_a_typed_conflict(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    first = records.client.put(f"{base}/{record_id}", json=update_body(records, "tasks"))
    assert first.status_code == 200, first.text
    stale = records.client.put(f"{base}/{record_id}", json=update_body(records, "tasks"))
    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "revision_conflict"


def test_tombstone_is_preserved_and_not_resurrected(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    removed = records.client.post(f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4())})
    assert removed.status_code == 200, removed.text
    stale = records.client.put(f"{base}/{record_id}", json=update_body(records, "tasks"))
    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "record_deleted"
    again = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert again.status_code == 409
    assert again.json()["error"]["code"] == "record_exists"
    assert records.client.get(f"{base}/{record_id}").status_code == 404
    feed = records.client.get(f"/farms/{records.ids.farm}/changes").json()
    assert [item["operation"] for item in feed["items"]] == ["create", "delete"]


def test_change_polling_resumes_from_a_cursor_without_gaps_or_duplicates(records):
    base = f"/farms/{records.ids.farm}/tasks"
    expected = []
    for _ in range(5):
        record_id = str(uuid4())
        expected.append(record_id)
        created = records.client.post(base, json=create_body(records, "tasks", record_id))
        assert created.status_code == 200, created.text
    seen = []
    cursor = 0
    for _ in range(10):
        page = records.client.get(
            f"/farms/{records.ids.farm}/changes?since={cursor}&limit=2"
        ).json()
        seen.extend(page["items"])
        if page["next_cursor"] is None:
            break
        cursor = page["next_cursor"]
    cursors = [item["cursor"] for item in seen]
    assert cursors == sorted(cursors)
    assert len(cursors) == len(set(cursors)) == 5
    assert [item["record_id"] for item in seen] == expected
    assert {item["record_type"] for item in seen} == {"task"}
    assert {item["version"] for item in seen} == {1}


@pytest.mark.parametrize("resource", RESOURCES)
def test_writes_to_a_foreign_farm_are_not_found(records, resource):
    base = f"/farms/{records.ids.foreign}/{resource}"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, resource, record_id))
    assert created.status_code == 404
    updated = records.client.put(f"{base}/{record_id}", json=update_body(records, resource))
    assert updated.status_code == 404
    removed = records.client.post(f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4())})
    assert removed.status_code == 404


def test_records_cannot_be_reached_through_another_owned_farm(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    other = f"/farms/{records.ids.second}/tasks/{record_id}"
    assert records.client.get(other).status_code == 404
    assert records.client.put(other, json=update_body(records, "tasks")).status_code == 404
    removed = records.client.post(f"{other}/delete", json={"mutation_id": str(uuid4())})
    assert removed.status_code == 404
    assert records.client.get(f"/farms/{records.ids.second}/changes").json()["items"] == []


def test_a_section_from_another_farm_cannot_be_referenced(records):
    payload = create_body(records, "tasks")
    payload["section_id"] = str(records.ids.second_section)
    response = records.client.post(f"/farms/{records.ids.farm}/tasks", json=payload)
    assert response.status_code == 404


@pytest.mark.parametrize("resource", RESOURCES)
def test_new_write_routes_require_a_session(records, resource):
    response = records.client.post(
        f"/farms/{records.ids.farm}/{resource}",
        json=create_body(records, resource),
        headers={"Authorization": ""},
    )
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_session"


def test_change_feed_requires_a_session_and_is_owner_scoped(records):
    unauthenticated = records.client.get(
        f"/farms/{records.ids.farm}/changes", headers={"Authorization": ""}
    )
    assert unauthenticated.status_code == 401
    assert records.client.get(f"/farms/{records.ids.foreign}/changes").status_code == 404


def test_observations_support_update_and_tombstone(records):
    base = f"/farms/{records.ids.farm}/observations"
    payload = observation_payload(records.ids)
    created = records.client.post(base, json=payload)
    assert created.status_code == 200, created.text
    record_id = payload["observation_id"]
    updated = records.client.put(
        f"{base}/{record_id}",
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 1,
            "type": "pest",
            "note": "Aphids found",
            "health_status": "poor",
        },
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["record"]["note"] == "Aphids found"
    assert updated.json()["version"] == 2
    removed = records.client.post(f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4())})
    assert removed.status_code == 200, removed.text
    assert records.client.get(f"{base}/{record_id}").status_code == 404


def test_section_detail_exposes_the_flutter_summary(records):
    farm = records.ids.farm
    section = str(records.ids.section)

    def create(resource, fields=None):
        body = create_body(records, resource)
        body.update(fields or {})
        response = records.client.post(f"/farms/{farm}/{resource}", json=body)
        assert response.status_code == 200, response.text

    create("plantings")
    create("tasks")
    create("financials")
    create("financials", {"type": "income", "category": "sale", "amount_cents": 10000})
    create("plans")
    observation = observation_payload(records.ids)
    observation["health_status"] = "healthy"
    created = records.client.post(f"/farms/{farm}/observations", json=observation)
    assert created.status_code == 200, created.text
    detail = records.client.get(f"/farms/{farm}/sections/{section}")
    assert detail.status_code == 200, detail.text
    body = detail.json()
    assert body["section"]["id"] == section
    assert body["current_planting"]["crop"] == "cabbage"
    assert body["current_plan"]["status"] == "saved"
    assert body["latest_health_status"] == "healthy"
    assert [item["id"] for item in body["observations"]] == [observation["observation_id"]]
    assert len(body["tasks"]) == 1
    assert body["financials"] == {
        "income_cents": 10000,
        "expense_cents": 4200,
        "net_cents": 5800,
    }
    foreign = records.client.get(f"/farms/{farm}/sections/{records.ids.foreign_section}")
    assert foreign.status_code == 404


@pytest.mark.parametrize(
    "field,value",
    [
        ("unknown_field", "x"),
        ("title", " "),
        ("title", "x" * 101),
        ("expected_cost_cents", -1),
        ("status", "archived"),
        ("due_date", "not-a-date"),
        ("id", "not-a-uuid"),
    ],
)
def test_task_requests_are_strictly_validated(records, field, value):
    payload = create_body(records, "tasks")
    payload[field] = value
    response = records.client.post(f"/farms/{records.ids.farm}/tasks", json=payload)
    assert response.status_code == 422


def test_put_bodies_are_bounded(records):
    response = records.client.put(
        f"/farms/{records.ids.farm}/tasks/{uuid4()}",
        content=iter([b"x" * 32768, b"x" * 32769]),
        headers={"Content-Type": "application/json"},
    )
    assert response.status_code == 413


@pytest.mark.parametrize(
    "model", EXAMPLE_MODELS, ids=[model.__name__ for model in EXAMPLE_MODELS]
)
def test_openapi_request_examples_validate(records, model):
    schema = records.app.openapi()["components"]["schemas"][model.__name__]
    assert schema["examples"], f"{model.__name__} has no OpenAPI example"
    for example in schema["examples"]:
        model.model_validate(example)


def test_openapi_documents_the_new_resource_routes(records):
    paths = records.app.openapi()["paths"]
    farm = "/farms/{farm_id}"
    assert f"{farm}/changes" in paths
    assert "get" in paths[f"{farm}/sections/{{record_id}}"]
    assert "put" in paths[f"{farm}/observations/{{record_id}}"]
    for resource in RESOURCES:
        item = f"{farm}/{resource}/{{record_id}}"
        assert "post" in paths[f"{farm}/{resource}"]
        assert "put" in paths[item]
        assert "post" in paths[f"{item}/delete"]
    for resource in READABLE:
        assert "get" in paths[f"{farm}/{resource}"]
        assert "get" in paths[f"{farm}/{resource}/{{record_id}}"]
    operations = [
        operation["operationId"]
        for path in paths.values()
        for method, operation in path.items()
        if method in ("get", "post", "put", "delete")
    ]
    assert len(operations) == len(set(operations))
    assert paths[f"{farm}/tasks"]["post"]["security"] == [{"SessionBearer": []}]
    assert "ErrorResponse" in str(paths[f"{farm}/tasks"]["post"]["responses"]["409"])
