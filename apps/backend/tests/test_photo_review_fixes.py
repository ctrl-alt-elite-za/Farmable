"""PR49 review regressions. Concurrent recovery is tested on PostgreSQL separately."""

import asyncio
import json
import logging
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import AsyncMock, Mock
from uuid import uuid4

import pytest
from farmable_backend import worker
from farmable_backend.logging import JsonFormatter
from farmable_backend.models import Observation, PhotoAttempt, PhotoRate, PhotoUpload, SyncMutation
from farmable_backend.photo_policy import MAX_CLAIMS, RETRY_DELAYS
from farmable_backend.record_access import ApiError
from farmable_backend.records_schemas import FarmView, SectionView
from sqlalchemy import func, select
from test_records_api import observation_payload, process, queue, reserve

pytest_plugins = ("test_records_api",)


def exhaust(records, upload, attempt):
    records.storage.failure = "storage_unavailable"
    for _ in range(MAX_CLAIMS):
        process(records, records.jobs.claim(upload.id))
        with records.sessions.begin() as session:
            session.get(PhotoAttempt, attempt.id).next_attempt_at = datetime.now(UTC) - timedelta(
                seconds=1
            )


def test_explicit_recovery_preserves_identity_and_fences_old_retries(records):
    payload, _, upload, attempt = queue(records)
    exhaust(records, upload, attempt)
    path = f"/farms/{records.ids.farm}/photo-uploads/{upload.id}"
    failed = records.client.get(path).json()
    assert failed["retryable"] is True
    assert failed["error_code"] == "temporarily_unavailable"
    assert (
        records.service.reserve(records.ids.authorization, records.ids.farm, payload)[0].state
        == "failed"
    )
    body = {"failed_attempt_id": str(attempt.id)}
    recovered = records.client.post(path + "/retry", json=body)
    assert recovered.status_code == 200
    assert recovered.headers["cache-control"] == "no-store"
    recovery = recovered.json()
    assert recovery["state"] == "awaiting_upload" and recovery["retryable"] is False
    assert "form" not in recovery and "cloud_media_id" not in recovery
    for key in ("upload_id", "mutation_id", "entity_id", "owner_id", "farm_id"):
        assert recovery[key] == failed[key]
    assert recovery["attempt_id"] != failed["attempt_id"]
    assert records.client.post(path + "/retry", json=body).json() == recovery
    _, _, second = records.service.reserve(records.ids.authorization, records.ids.farm, payload)
    records.service.upload(records.ids.authorization, records.ids.farm, upload.id, complete=True)
    exhaust(records, upload, second)
    late = records.client.post(path + "/retry", json=body).json()
    assert late["state"] == "failed" and late["attempt_id"] == str(second.id)
    with records.sessions() as session:
        assert session.get(PhotoAttempt, second.id).attempt_count == MAX_CLAIMS
        assert session.scalar(select(func.count()).select_from(PhotoAttempt)) == 2
    body = {"failed_attempt_id": str(second.id)}
    assert records.client.post(path + "/retry", json=body).status_code == 200
    _, _, third = records.service.reserve(records.ids.authorization, records.ids.farm, payload)
    assert third.attempt_count == 0
    records.storage.failure = None
    records.service.upload(records.ids.authorization, records.ids.farm, upload.id, complete=True)
    process(records)
    ready = records.client.get(path).json()
    assert ready["cloud_media_id"] == str(upload.media_id)
    assert records.client.post(path + "/retry", json=body).json() == ready
    assert (
        records.client.post(path + "/retry", json={"failed_attempt_id": str(third.id)}).status_code
        == 409
    )


@pytest.mark.parametrize("state", ["awaiting_upload", "queued", "processing", "failed"])
def test_retry_rejects_active_or_permanently_invalid_attempts(records, state):
    _, _, upload, attempt = reserve(records)
    with records.sessions.begin() as session:
        row = session.get(PhotoUpload, upload.id)
        row.state, row.error_code = state, "invalid_photo" if state == "failed" else None
    path = f"/farms/{records.ids.farm}/photo-uploads/{upload.id}/retry"
    result = records.client.post(path, json={"failed_attempt_id": str(attempt.id)})
    assert result.status_code == 409
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(PhotoAttempt)) == 1


def test_retry_checks_scope_unknown_attempts_strict_input_and_quota(records):
    _, _, upload, attempt = queue(records)
    exhaust(records, upload, attempt)
    _, _, _, other_attempt = reserve(records)
    base = f"/farms/{records.ids.farm}/photo-uploads/{upload.id}"
    body = {"failed_attempt_id": str(attempt.id)}
    for wrong_id in (other_attempt.id, uuid4()):
        assert (
            records.client.post(
                base + "/retry", json={"failed_attempt_id": str(wrong_id)}
            ).status_code
            == 404
        )
    assert (
        records.client.post(
            base.replace(str(records.ids.farm), str(records.ids.second)) + "/retry", json=body
        ).status_code
        == 404
    )
    assert records.client.post(base + "/retry", json={**body, "byte_length": 1}).status_code == 422
    with records.sessions.begin() as session:
        session.get(PhotoRate, records.ids.owner).hits = [datetime.now(UTC).timestamp()] * 30
    limited = records.client.post(base + "/retry", json=body)
    assert limited.status_code == 429 and limited.headers["retry-after"]
    assert records.client.get(base).json()["state"] == "failed"


@pytest.mark.parametrize(
    "code,public,retryable",
    [
        ("private_bucket_unverified", "temporarily_unavailable", True),
        ("storage_unavailable", "temporarily_unavailable", True),
        ("incoming_missing", "temporarily_unavailable", True),
        ("retry_exhausted", "temporarily_unavailable", True),
        ("scope_unavailable", "target_unavailable", False),
        ("photo_dimensions_too_large", "invalid_photo", False),
        ("private_bucket_required", "temporarily_unavailable", True),
        ("provider-secret-detail", "upload_failed", False),
    ],
)
def test_http_photo_failure_vocabulary_is_allowlisted(records, code, public, retryable):
    _, _, upload, _ = reserve(records)
    with records.sessions.begin() as session:
        row = session.get(PhotoUpload, upload.id)
        row.state, row.error_code = "failed", code
    result = records.client.get(f"/farms/{records.ids.farm}/photo-uploads/{upload.id}")
    assert result.json()["error_code"] == public
    assert result.json()["retryable"] is retryable
    assert code not in result.text


@pytest.mark.parametrize(
    "offset,status",
    [
        (timedelta(days=-365), 200),
        (timedelta(minutes=5), 200),
        (timedelta(days=-365, microseconds=-1), 422),
        (timedelta(minutes=5, microseconds=1), 422),
    ],
)
def test_observation_time_window_is_inclusive(records, monkeypatch, offset, status):
    now = datetime.now(UTC)
    monkeypatch.setattr("farmable_backend.records_service.db_now", lambda _: now)
    payload = observation_payload(records.ids)
    payload["created_at"] = (now + offset).isoformat()
    response = records.client.post(f"/farms/{records.ids.farm}/observations", json=payload)
    assert response.status_code == status
    with records.sessions() as session:
        for model in (Observation, SyncMutation):
            assert session.scalar(select(func.count()).select_from(model)) == (status == 200)


@pytest.mark.parametrize("timestamp", ["1900-01-01T00:00:00Z", "9999-01-01T00:00:00Z"])
def test_absurd_observation_dates_are_rejected(records, timestamp):
    payload = observation_payload(records.ids)
    payload["created_at"] = timestamp
    assert (
        records.client.post(f"/farms/{records.ids.farm}/observations", json=payload).status_code
        == 422
    )


def test_accepted_observation_replay_does_not_age_out_or_allow_changed_payload(
    records, monkeypatch
):
    now = datetime.now(UTC)
    monkeypatch.setattr("farmable_backend.records_service.db_now", lambda _: now)
    payload = observation_payload(records.ids)
    payload["created_at"] = (now - timedelta(days=364)).isoformat()
    path = f"/farms/{records.ids.farm}/observations"
    first = records.client.post(path, json=payload)
    assert first.status_code == 200
    monkeypatch.setattr(
        "farmable_backend.records_service.db_now", lambda _: now + timedelta(days=2)
    )
    assert records.client.post(path, json=payload).json() == first.json()
    assert records.client.post(path, json={**payload, "note": "changed"}).status_code == 409


def test_single_record_dispatch_and_unordered_quota(records, monkeypatch):
    service, ids = records.service, records.ids
    assert isinstance(
        service.read(ids.authorization, "farms", None, None, ids.farm, None, 1), FarmView
    )
    assert isinstance(
        service.read(ids.authorization, "sections", ids.farm, None, ids.section, None, 1),
        SectionView,
    )
    now = datetime.now(UTC)
    monkeypatch.setattr("farmable_backend.records_service.db_now", lambda _: now)
    service.photo_rate(ids.authorization)
    with records.sessions.begin() as session:
        session.get(PhotoRate, ids.owner).hits = [now.timestamp() - 10] * 29 + [
            now.timestamp() - 50
        ]
    with pytest.raises(ApiError) as error:
        service.photo_rate(ids.authorization)
    assert error.value.retry_after == 10


@pytest.mark.parametrize(
    "name", ["google", "google.auth", "urllib3", "urllib3.pool", "requests", "requests.sessions"]
)
def test_vendor_root_and_descendant_logs_are_opaque(name):
    record = logging.LogRecord(
        name, logging.DEBUG, "", 1, "https://secret.invalid?token=abc", (), None
    )
    assert json.loads(JsonFormatter().format(record))["message"] == "Storage transport event"


def test_claim_budget_tracks_retry_schedule():
    assert MAX_CLAIMS == len(RETRY_DELAYS) + 1


@pytest.mark.parametrize(
    "configured,constructor_fails,queue_fails",
    [
        (False, False, False),
        (True, False, False),
        (True, True, False),
        (True, False, True),
    ],
)
def test_photo_worker_resources_are_optional_and_always_closed(
    monkeypatch, configured, constructor_fails, queue_fails
):
    @asynccontextmanager
    async def opened():
        yield

    photo = SimpleNamespace(stop=asyncio.Event(), executor=Mock())
    photo.run = AsyncMock(side_effect=photo.stop.wait)
    database = Mock()
    database_factory = Mock(return_value=database)
    photo_factory = Mock(
        return_value=photo, side_effect=RuntimeError("constructor") if constructor_fails else None
    )

    async def run_queue(**kwargs):
        await asyncio.sleep(0)
        if queue_fails:
            raise RuntimeError("queue")

    app = Mock(open_async=opened, run_worker_async=AsyncMock(side_effect=run_queue))
    monkeypatch.setattr(
        worker, "ServiceSettings", lambda: SimpleNamespace(integrations_mode="disabled")
    )
    monkeypatch.setattr(
        worker,
        "Settings",
        lambda: SimpleNamespace(photo_bucket="unit" if configured else None, log_level="info"),
    )
    monkeypatch.setattr(worker, "configure_logging", Mock())
    monkeypatch.setattr(worker, "create_task_app", lambda _: app)
    monkeypatch.setattr(worker, "Database", database_factory)
    monkeypatch.setattr(worker, "PhotoWorker", photo_factory)
    if constructor_fails or queue_fails:
        with pytest.raises(RuntimeError):
            asyncio.run(worker.run())
    else:
        asyncio.run(worker.run())
    if configured:
        database.close.assert_called_once()
        if not constructor_fails:
            assert photo.stop.is_set()
            photo.run.assert_awaited_once()
    else:
        database_factory.assert_not_called()
        photo_factory.assert_not_called()
