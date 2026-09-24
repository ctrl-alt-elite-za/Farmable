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
    "plantings": lambda ids: {"crop": "spinach", "planted_on": "2026-08-02"},
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
    removed = records.client.post(
        f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4()), "expected_version": 2}
    )
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
    removed = records.client.post(
        f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4()), "expected_version": 1}
    )
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
    body = response.json()
    assert body["error"]["code"] == "record_conflict"
    assert body["error"].keys() == {"code", "message"}
    assert str(records.ids.other) not in response.text
    assert "Not yours" not in response.text


def test_cross_owner_collision_is_not_reported_as_record_exists(records):
    """A same-owner id clash still reports record_exists (that leaks nothing new:
    it is telling the caller about their own data). A cross-owner clash must never
    be conflated with that code, or a client could tell owned ids from unowned ones
    by the error code alone."""
    from datetime import date

    from farmable_backend.models import FarmTask

    base = f"/farms/{records.ids.farm}/tasks"

    own_id = uuid4()
    own = create_body(records, "tasks", str(own_id))
    assert records.client.post(base, json=own).status_code == 200
    own_again = create_body(records, "tasks", str(own_id))
    own_response = records.client.post(base, json=own_again)
    assert own_response.status_code == 409
    assert own_response.json()["error"]["code"] == "record_exists"

    foreign_id = uuid4()
    with records.sessions.begin() as session:
        session.add(
            FarmTask(
                id=foreign_id,
                farm_id=records.ids.foreign,
                owner_id=records.ids.other,
                section_id=records.ids.foreign_section,
                title="Not yours",
                due_date=date(2026, 10, 1),
            )
        )
    foreign_colliding = create_body(records, "tasks", str(foreign_id))
    foreign_response = records.client.post(base, json=foreign_colliding)
    assert foreign_response.status_code == 409
    assert foreign_response.json()["error"]["code"] == "record_conflict"


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


def test_deleting_with_omitted_expected_version_is_rejected(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    removed = records.client.post(f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4())})
    assert removed.status_code == 422
    assert records.client.get(f"{base}/{record_id}").status_code == 200


def test_deleting_with_null_expected_version_is_rejected(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    removed = records.client.post(
        f"{base}/{record_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": None},
    )
    assert removed.status_code == 422
    assert records.client.get(f"{base}/{record_id}").status_code == 200


def test_a_delayed_offline_delete_cannot_silently_erase_a_newer_edit(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    updated = records.client.put(f"{base}/{record_id}", json=update_body(records, "tasks"))
    assert updated.status_code == 200, updated.text
    assert updated.json()["version"] == 2
    stale = records.client.post(
        f"{base}/{record_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": 1},
    )
    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "revision_conflict"
    assert records.client.get(f"{base}/{record_id}").json()["title"] == "Weed again"
    with records.sessions() as session:
        assert (
            session.scalar(
                select(func.count())
                .select_from(SyncChange)
                .where(SyncChange.record_id == UUID(record_id), SyncChange.operation == "delete")
            )
            == 0
        )


def test_deleting_an_already_deleted_record_still_enforces_expected_version(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    first_delete = records.client.post(
        f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4()), "expected_version": 1}
    )
    assert first_delete.status_code == 200, first_delete.text
    current_version = first_delete.json()["version"]
    stale = records.client.post(
        f"{base}/{record_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": current_version + 1},
    )
    assert stale.status_code == 409
    assert stale.json()["error"]["code"] == "revision_conflict"


def test_deleting_an_already_deleted_record_with_matching_expected_version_succeeds(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    first_delete = records.client.post(
        f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4()), "expected_version": 1}
    )
    assert first_delete.status_code == 200, first_delete.text
    current_version = first_delete.json()["version"]
    again = records.client.post(
        f"{base}/{record_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": current_version},
    )
    assert again.status_code == 200, again.text


def test_deleting_with_correct_expected_version_succeeds(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    removed = records.client.post(
        f"{base}/{record_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": 1},
    )
    assert removed.status_code == 200, removed.text
    assert records.client.get(f"{base}/{record_id}").status_code == 404


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
    delete_payload = {"mutation_id": str(uuid4()), "expected_version": 1}
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
    removed = records.client.post(
        f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4()), "expected_version": 1}
    )
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
    removed = records.client.post(
        f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4()), "expected_version": 1}
    )
    assert removed.status_code == 404


def test_records_cannot_be_reached_through_another_owned_farm(records):
    base = f"/farms/{records.ids.farm}/tasks"
    record_id = str(uuid4())
    created = records.client.post(base, json=create_body(records, "tasks", record_id))
    assert created.status_code == 200, created.text
    other = f"/farms/{records.ids.second}/tasks/{record_id}"
    assert records.client.get(other).status_code == 404
    assert records.client.put(other, json=update_body(records, "tasks")).status_code == 404
    removed = records.client.post(
        f"{other}/delete", json={"mutation_id": str(uuid4()), "expected_version": 1}
    )
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
    removed = records.client.post(
        f"{base}/{record_id}/delete", json={"mutation_id": str(uuid4()), "expected_version": 2}
    )
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


def test_new_account_has_no_sections(records):
    from farmable_backend.models import Farm

    with records.sessions.begin() as session:
        new_farm = Farm(owner_id=records.ids.owner, name="Brand new")
        session.add(new_farm)
        session.flush()
        new_farm_id = new_farm.id
    response = records.client.get(f"/farms/{new_farm_id}/sections")
    assert response.status_code == 200, response.text
    assert response.json()["items"] == []


def test_section_kind_defaults_to_crop_and_accepts_animal(records):
    base = f"/farms/{records.ids.farm}/sections"
    default_kind = records.client.post(base, json=create_body(records, "sections"))
    assert default_kind.status_code == 200, default_kind.text
    assert default_kind.json()["record"]["kind"] == "crop"

    animal_id = str(uuid4())
    animal_body = create_body(records, "sections", animal_id)
    animal_body["kind"] = "animal"
    animal = records.client.post(base, json=animal_body)
    assert animal.status_code == 200, animal.text
    assert animal.json()["record"]["kind"] == "animal"
    # GET .../sections/{id} returns the Flutter section-detail summary, not a bare SectionView.
    assert records.client.get(f"{base}/{animal_id}").json()["section"]["kind"] == "animal"


def test_crop_harvest_window_from_calendar(records):
    base = f"/farms/{records.ids.farm}/plantings"
    body = create_body(records, "plantings")
    body["crop_type_code"] = "cabbage"
    body["planted_on"] = "2026-09-01"
    created = records.client.post(base, json=body)
    assert created.status_code == 200, created.text
    planting = created.json()["record"]
    assert planting["crop_type_code"] == "cabbage"
    assert planting["harvest_from"] == "2026-11-30"  # 2026-09-01 + 90 days
    assert planting["harvest_to"] == "2026-12-20"  # 2026-09-01 + 110 days


def test_unknown_crop_rejected(records):
    base = f"/farms/{records.ids.farm}/plantings"
    body = create_body(records, "plantings")
    body["crop_type_code"] = "banana"
    response = records.client.post(base, json=body)
    assert response.status_code == 422, response.text
    assert response.json()["error"]["code"] == "unknown_crop_type"


def test_planted_on_out_of_range_rejected(records):
    base = f"/farms/{records.ids.farm}/plantings"
    body = create_body(records, "plantings")
    body["crop_type_code"] = "cabbage"
    body["planted_on"] = "2000-01-01"
    response = records.client.post(base, json=body)
    assert response.status_code == 422, response.text
    assert response.json()["error"]["code"] == "planted_on_out_of_range"


def test_legacy_crop_text_is_preserved_and_old_planting_edits_sync(records):
    base = f"/farms/{records.ids.farm}/plantings"
    planting_id = str(uuid4())
    created = records.client.post(
        base,
        json={
            "mutation_id": str(uuid4()),
            "id": planting_id,
            "section_id": str(records.ids.section),
            "crop": "Butternut",
            "planted_on": "2000-01-01",
            "is_current": False,
        },
    )
    assert created.status_code == 200, created.text
    assert created.json()["record"]["crop"] == "Butternut"
    assert created.json()["record"]["crop_type_code"] is None

    updated = records.client.put(
        f"{base}/{planting_id}",
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 1,
            "crop": "Butternut",
            "planted_on": "2000-01-01",
            "is_current": False,
        },
    )
    assert updated.status_code == 200, updated.text
    assert updated.json()["record"]["crop"] == "Butternut"


def test_section_delete_requires_versions_for_attached_children(records):
    section_id = str(uuid4())
    assert (
        records.client.post(
            f"/farms/{records.ids.farm}/sections",
            json=create_body(records, "sections", section_id),
        ).status_code
        == 200
    )
    planting = create_body(records, "plantings")
    planting["section_id"] = section_id
    assert (
        records.client.post(f"/farms/{records.ids.farm}/plantings", json=planting).status_code
        == 200
    )
    delete = records.client.post(
        f"/farms/{records.ids.farm}/sections/{section_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": 1},
    )
    assert delete.status_code == 409
    assert delete.json()["error"]["code"] == "revision_conflict"

    delete = records.client.post(
        f"/farms/{records.ids.farm}/sections/{section_id}/delete",
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 1,
            "expected_child_versions": {planting["id"]: 1},
        },
    )
    assert delete.status_code == 200, delete.text


def test_delete_section_cascades(records):
    farm = records.ids.farm
    section_id = str(uuid4())
    section = records.client.post(
        f"/farms/{farm}/sections",
        json=create_body(records, "sections", section_id),
    )
    assert section.status_code == 200, section.text

    attached = {}
    for resource in ("plantings", "tasks", "financials", "plans", "media"):
        body = create_body(records, resource)
        body["section_id"] = section_id
        created = records.client.post(f"/farms/{farm}/{resource}", json=body)
        assert created.status_code == 200, created.text
        attached[resource] = body["id"]
    observation = observation_payload(records.ids)
    observation["section_id"] = section_id
    created_observation = records.client.post(f"/farms/{farm}/observations", json=observation)
    assert created_observation.status_code == 200, created_observation.text
    attached["observations"] = observation["observation_id"]

    expected_child_versions = {record_id: 1 for record_id in attached.values()}

    before = records.client.get(f"/farms/{farm}/changes?since=0&limit=100").json()
    change_count_before = len(before["items"])

    delete = records.client.post(
        f"/farms/{farm}/sections/{section_id}/delete",
        json={
            "mutation_id": str(uuid4()),
            "expected_version": 1,
            "expected_child_versions": expected_child_versions,
        },
    )
    assert delete.status_code == 200, delete.text

    for resource, record_id in attached.items():
        get = records.client.get(f"/farms/{farm}/{resource}/{record_id}")
        assert get.status_code == 404, f"{resource} not tombstoned: {get.text}"
    with records.sessions() as session:
        from farmable_backend.models import (
            FarmTask,
            FinancialRecord,
            Media,
            Observation,
            Planting,
            PlantingCrop,
            SavedPlan,
        )

        for model, record_id in zip(
            (Planting, FarmTask, FinancialRecord, SavedPlan, Media, Observation),
            (
                attached["plantings"],
                attached["tasks"],
                attached["financials"],
                attached["plans"],
                attached["media"],
                attached["observations"],
            ),
            strict=True,
        ):
            row = session.get(model, UUID(record_id))
            assert row is not None
            assert row.deleted_at is not None
        assert session.get(PlantingCrop, UUID(attached["plantings"])) is None

    after = records.client.get(f"/farms/{farm}/changes?since=0&limit=100").json()
    # The section tombstone plus one SyncChange per attached record.
    assert len(after["items"]) == change_count_before + 1 + len(attached)

    # Safe to run twice: a second, different mutation against the already-deleted
    # section must not error and must not double-tombstone or double-publish.
    delete_again = records.client.post(
        f"/farms/{farm}/sections/{section_id}/delete",
        json={"mutation_id": str(uuid4()), "expected_version": delete.json()["version"]},
    )
    assert delete_again.status_code == 200, delete_again.text
    again = records.client.get(f"/farms/{farm}/changes?since=0&limit=100").json()
    assert len(again["items"]) == len(after["items"]) + 1  # only the section's own change row


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


@pytest.mark.parametrize("model", EXAMPLE_MODELS, ids=[model.__name__ for model in EXAMPLE_MODELS])
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
