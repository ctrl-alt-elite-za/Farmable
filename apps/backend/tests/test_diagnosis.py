"""Real queue/HTTP boundaries with isolated fake providers, never paid requests."""

import asyncio
import copy
import io
import json
from datetime import UTC, datetime, timedelta
from pathlib import Path
from uuid import UUID, uuid4

import pytest
from alembic import command
from alembic.config import Config
from farmable_backend.account import AccountService
from farmable_backend.diagnosis import DiagnosisStore
from farmable_backend.diagnosis_worker import DiagnosisWorker, normalized
from farmable_backend.integrations.base import ServiceResult
from farmable_backend.integrations.crop_health import CropHealth
from farmable_backend.models import CropDiagnosis, Media, Planting, Section
from test_records_api import process, queue
from test_vision_schema import _index_statements, _orm_sql, _table_elements

pytest_plugins = ("test_records_api",)
ROOT = Path(__file__).resolve().parents[3]


def setup(records, crop="tomato"):
    records.app.state.diagnosis_enabled = True
    _, _, upload, _ = queue(records)
    process(records)
    with records.sessions.begin() as session:
        planting = Planting(
            id=uuid4(),
            owner_id=records.ids.owner,
            farm_id=records.ids.farm,
            section_id=records.ids.section,
            crop=crop,
        )
        session.add(planting)
        session.flush()
    body = {
        "id": str(uuid4()),
        "media_id": str(upload.media_id),
        "planting_id": str(planting.id),
        "consent_notice_version": "crop-health-v1",
    }
    base = f"/farms/{records.ids.farm}"
    return (
        body,
        f"{base}/sections/{records.ids.section}/diagnoses",
        f"{base}/diagnoses/{body['id']}",
    )


def worker(records):
    records.storage.read_clean = lambda upload, attempt: records.storage.published[attempt.id]
    registry = records.app.state.services
    return DiagnosisWorker(
        records.sessions,
        CropHealth("crop_health", registry.client, registry.crop_health.settings, max_attempts=1),
        lambda: records.storage,
    )


def execute(records, identifier):
    instance = worker(records)
    try:
        claimed = instance.jobs.claim(UUID(identifier))
        assert claimed is not None
        asyncio.run(instance.process(claimed))
    finally:
        instance.executor.shutdown()


def sample():
    return json.loads(
        (
            ROOT / "apps/backend/src/farmable_backend/integrations/fixtures/provider_examples.json"
        ).read_text()
    )["success"]["crop_health"]


def test_submit_process_poll_and_exact_replay(records):
    body, path, get = setup(records)
    response = records.client.post(path, json=body)
    assert response.status_code == 202
    assert response.json()["state"] == "queued"
    assert records.client.post(path, json=body).json() == response.json()
    execute(records, body["id"])
    result = records.client.get(get)
    assert result.status_code == 200
    assert result.json()["state"] == "ready"
    assert result.json()["result"]["data_kind"] == "synthetic"
    assert result.json()["result"]["suggestions"][0]["name"] == "Early blight"
    assert "access_token" not in result.text and "object_key" not in result.text
    assert records.client.post(path, json=body).json()["state"] == "ready"
    assert len(records.client.get(f"/farms/{records.ids.farm}/diagnoses").json()["items"]) == 1


@pytest.mark.parametrize("crop", ["cabbage", "spinach", "unknown crop"])
def test_unsupported_crops_are_honest_terminal_results_without_provider_call(records, crop):
    body, path, get = setup(records, crop)
    response = records.client.post(path, json=body)
    assert response.status_code == 202
    assert response.json()["error"] == "unsupported_crop"
    assert DiagnosisStore(records.sessions).claim(UUID(body["id"])) is None
    assert records.client.get(get).json()["result"] is None


@pytest.mark.parametrize(
    "field,value",
    [("consent_notice_version", "old"), ("media_id", str(uuid4())), ("planting_id", str(uuid4()))],
)
def test_rejects_missing_inputs_and_stale_consent(records, field, value):
    body, path, _ = setup(records)
    body[field] = value
    assert records.client.post(path, json=body).status_code in {404, 422}


def test_owner_and_farm_isolation(records):
    body, path, get = setup(records)
    assert (
        records.client.post(
            path.replace(str(records.ids.farm), str(records.ids.foreign)), json=body
        ).status_code
        == 404
    )
    assert (
        records.client.post(
            path.replace(str(records.ids.farm), str(records.ids.second)), json=body
        ).status_code
        == 404
    )
    records.client.post(path, json=body)
    assert (
        records.client.get(get.replace(str(records.ids.farm), str(records.ids.second))).status_code
        == 404
    )
    assert records.client.get(get, headers={"Authorization": "Bearer invalid"}).status_code == 401


def test_idempotency_rejects_changed_input_and_pending_quota_is_durable(records):
    body, path, _ = setup(records)
    assert records.client.post(path, json=body).status_code == 202
    assert records.client.post(path, json={**body, "media_id": str(uuid4())}).status_code == 409
    for _ in range(3):
        assert records.client.post(path, json={**body, "id": str(uuid4())}).status_code == 202
    assert records.client.post(path, json={**body, "id": str(uuid4())}).status_code == 429
    assert records.client.post(path, json=body).status_code == 202


def test_cancel_fences_late_result_and_replay_cannot_regrant(records):
    body, path, get = setup(records)
    records.client.post(path, json=body)
    store = DiagnosisStore(records.sessions)
    row, _, _ = store.claim(UUID(body["id"]))
    assert records.client.post(get + "/cancel").json()["state"] == "cancelled"
    assert not store.finish(
        row.id, row.lease_token, result=normalized(sample(), "tomato", synthetic=True)
    )
    assert records.client.post(path, json=body).json()["state"] == "cancelled"
    assert records.client.get(get).json()["result"] is None


def test_claim_is_single_use_and_crashed_paid_attempt_is_not_resubmitted(records):
    body, path, get = setup(records)
    records.client.post(path, json=body)
    store = DiagnosisStore(records.sessions)
    row, _, _ = store.claim(UUID(body["id"]))
    assert store.claim(row.id) is None
    with records.sessions.begin() as session:
        session.get(CropDiagnosis, row.id).lease_expires_at = datetime.now(UTC) - timedelta(
            seconds=1
        )
    assert store.claim(row.id) is None
    assert records.client.get(get).json()["error"] == "delivery_unknown"
    assert not store.finish(
        row.id, row.lease_token, result=normalized(sample(), "tomato", synthetic=True)
    )


@pytest.mark.parametrize("change", ["media", "planting", "section"])
def test_scope_changes_fence_publication(records, change):
    body, path, get = setup(records)
    records.client.post(path, json=body)
    store = DiagnosisStore(records.sessions)
    row, _, _ = store.claim(UUID(body["id"]))
    with records.sessions.begin() as session:
        if change == "media":
            session.get(Media, UUID(body["media_id"])).deleted_at = datetime.now(UTC)
        elif change == "planting":
            session.get(Planting, UUID(body["planting_id"])).version += 1
        else:
            session.get(Section, records.ids.section).deleted_at = datetime.now(UTC)
    assert not store.finish(
        row.id, row.lease_token, result=normalized(sample(), "tomato", synthetic=True)
    )
    assert records.client.get(get).json()["error"] == "scope_unavailable"


def test_circuit_refusal_queues_bounded_retry_and_retains_photo(records):
    body, path, get = setup(records)
    records.client.post(path, json=body)
    instance = worker(records)
    instance.adapter.settings.fault_crop_health = True
    try:
        for number in range(3):
            claimed = instance.jobs.claim(UUID(body["id"]))
            assert claimed is not None
            asyncio.run(instance.process(claimed))
            result = records.client.get(get).json()
            assert result["state"] == ("queued" if number < 2 else "unavailable")
            with records.sessions.begin() as session:
                session.get(CropDiagnosis, UUID(body["id"])).next_attempt_at = datetime.now(
                    UTC
                ) - timedelta(seconds=1)
        assert result["error"] == "provider_unavailable"
        assert records.storage.published
    finally:
        instance.executor.shutdown()


def test_timeout_does_not_retry_an_ambiguously_billed_request(records):
    body, path, get = setup(records)
    records.client.post(path, json=body)
    instance = worker(records)

    async def timeout(images):
        return ServiceResult("crop_health", False, error="timeout")

    instance.adapter.identify = timeout
    try:
        asyncio.run(instance.process(instance.jobs.claim(UUID(body["id"]))))
        assert records.client.get(get).json()["error"] == "delivery_unknown"
        assert instance.jobs.claim(UUID(body["id"])) is None
    finally:
        instance.executor.shutdown()


@pytest.mark.parametrize("change", ["shape", "crop", "nonfinite", "empty", "not_plant"])
def test_untrusted_provider_payloads_are_rejected(change):
    data = copy.deepcopy(sample())
    if change == "shape":
        data["result"] = []
    elif change == "crop":
        data["result"]["crop"]["suggestions"][0].update(name="potato", scientific_name="potato")
    elif change == "nonfinite":
        data["result"]["disease"]["suggestions"][0]["probability"] = float("nan")
    elif change == "empty":
        data["result"]["disease"]["suggestions"] = []
    else:
        data["result"]["is_plant"]["binary"] = False
    with pytest.raises(ValueError):
        normalized(data, "tomato", synthetic=False)


def test_account_export_includes_diagnosis(records):
    body, path, _ = setup(records)
    records.client.post(path, json=body)
    document = AccountService(records.sessions).export_document(records.ids.authorization)
    assert document["crop_diagnoses"][0]["id"] == body["id"]


def test_operator_disabled_diagnosis_does_not_admit_work(records):
    body, path, _ = setup(records)
    records.app.state.diagnosis_enabled = False
    assert records.client.post(path, json=body).status_code == 503
    with records.sessions() as session:
        assert session.get(CropDiagnosis, UUID(body["id"])) is None


def test_account_erasure_deletes_diagnoses_and_fences_inflight_result(records):
    from farmable_backend.auth import PASSWORD_HASHER
    from farmable_backend.models import AuthIdentity

    body, path, _ = setup(records)
    records.client.post(path, json=body)
    store = DiagnosisStore(records.sessions)
    row, _, _ = store.claim(UUID(body["id"]))
    with records.sessions.begin() as session:
        session.get(AuthIdentity, records.ids.owner).password_hash = PASSWORD_HASHER.hash(
            "fixture-pass"
        )
    AccountService(records.sessions).delete_account(records.ids.authorization, "fixture-pass")
    with records.sessions() as session:
        assert session.get(CropDiagnosis, row.id) is None
    assert not store.finish(
        row.id, row.lease_token, result=normalized(sample(), "tomato", synthetic=True)
    )


def test_migration_matches_diagnosis_orm():
    output = io.StringIO()
    config = Config(str(ROOT / "alembic.ini"), output_buffer=output)
    config.set_main_option("script_location", str(ROOT / "migrations"))
    command.upgrade(config, "0014:0015", sql=True)
    sql = output.getvalue()
    assert _table_elements(sql, "crop_diagnoses") == _table_elements(
        _orm_sql("crop_diagnoses"), "crop_diagnoses"
    )
    assert _index_statements(sql, "crop_diagnoses") == _index_statements(
        _orm_sql("crop_diagnoses"), "crop_diagnoses"
    )
