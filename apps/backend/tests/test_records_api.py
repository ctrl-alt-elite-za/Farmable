"""HTTP and durable-intent regressions. Real GCS acceptance remains separate."""

import asyncio
import hashlib
import threading
from datetime import UTC, datetime, timedelta, timezone
from io import BytesIO
from types import SimpleNamespace
from uuid import uuid4

import pytest
from farmable_backend.gcs_photos import ObjectInfo
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.main import create_app
from farmable_backend.models import (
    AuthIdentity,
    AuthSession,
    Base,
    CropCalendar,
    CropType,
    Farm,
    Media,
    Observation,
    PhotoAttempt,
    Section,
    SyncChange,
    SyncMutation,
    User,
)
from farmable_backend.photo_jobs import PhotoJobs
from farmable_backend.photo_worker import PhotoWorker
from farmable_backend.record_access import ApiError, utc
from farmable_backend.records_api import RecordRuntime
from farmable_backend.records_schemas import ObservationCreate, UploadCreate
from farmable_backend.records_service import RecordsService
from farmable_backend.uploads import PostUpload, UploadError
from fastapi.testclient import TestClient
from PIL import Image
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool


def seed(sessions):
    token = "a" * 43
    with sessions.begin() as session:
        owner = User(id=uuid4())
        other = User(id=uuid4())
        session.add_all([owner, other])
        session.flush()
        identity = AuthIdentity(
            id=owner.id,
            first_name="Test",
            surname="Farmer",
            email=f"{owner.id}@example.com",
            phone=str(owner.id)[:20],
            password_hash="not-used",  # noqa: S106 -- synthetic identity, never password login.
            phone_verified=True,
            email_verified=True,
        )
        session.add(identity)
        session.flush()
        session.add(
            AuthSession(
                user_id=owner.id,
                access_token_hash=hashlib.sha256(token.encode()).hexdigest(),
                refresh_token_hash=hashlib.sha256(b"refresh-only").hexdigest(),
                expires_at=datetime.now(UTC) + timedelta(hours=1),
            )
        )
        farm = Farm(owner_id=owner.id, name="Owned")
        foreign = Farm(owner_id=other.id, name="Private")
        second = Farm(owner_id=owner.id, name="Second")
        session.add_all([farm, foreign, second])
        session.flush()
        section = Section(owner_id=owner.id, farm_id=farm.id, name="Cabbage")
        foreign_section = Section(owner_id=other.id, farm_id=foreign.id, name="Private")
        second_section = Section(owner_id=owner.id, farm_id=second.id, name="Second")
        session.add_all([section, foreign_section, second_section])
        session.flush()
        # Same invented, illustrative figures as migrations/versions/0018 (#11).
        # Idempotent: this seed() is shared by real-Postgres integration fixtures
        # whose search_path can fall back to a schema the migration already seeded.
        if session.get(CropType, "cabbage") is None:
            session.add_all(
                [
                    CropType(code="cabbage", name="Cabbage"),
                    CropType(code="spinach", name="Spinach"),
                ]
            )
            session.add_all(
                [
                    CropCalendar(
                        crop_type_code="cabbage", harvest_days_min=90, harvest_days_max=110
                    ),
                    CropCalendar(
                        crop_type_code="spinach", harvest_days_min=35, harvest_days_max=50
                    ),
                ]
            )
            session.flush()
        return SimpleNamespace(
            owner=owner.id,
            other=other.id,
            farm=farm.id,
            foreign=foreign.id,
            second=second.id,
            section=section.id,
            foreign_section=foreign_section.id,
            second_section=second_section.id,
            authorization=f"Bearer {token}",
        )


class FakeStorage:
    def __init__(self):
        with BytesIO() as output:
            Image.new("RGB", (2, 3)).save(output, "PNG")
            self.data = output.getvalue()
        self.generation = "1"
        self.read_generations = []
        self.failure = None
        self.published = {}
        self.cleaned = []

    def private(self):
        pass

    def prepare(self, upload, attempt):
        return PostUpload("https://storage.example.test/private", {"credential": "secret-form"})

    def inspect(self, upload, attempt):
        if self.failure:
            raise UploadError(self.failure)
        return ObjectInfo(attempt.source_generation or self.generation, len(self.data), "image/png")

    def read(self, upload, attempt):
        self.read_generations.append(attempt.source_generation)
        return self.data

    def publish(self, upload, attempt, clean):
        self.published.setdefault(attempt.id, clean.data)
        assert self.published[attempt.id] == clean.data
        return "42"

    def cleanup(self, upload, attempt, *, keep_clean, should_stop=lambda: False):
        if should_stop():
            return False
        self.cleaned.append((upload.id, attempt.id, keep_clean))
        return True

    def close(self):
        pass


@pytest.fixture
def records(settings):
    # Sequential HTTP/unit checks use memory, like the existing ORM unit suite.
    # Real concurrent transactions are tested against isolated PostgreSQL below.
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )
    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine, expire_on_commit=False)
    ids = seed(sessions)
    service = RecordsService(sessions)
    storage = FakeStorage()
    app = create_app(
        settings,
        readiness=lambda: {"database": "ok", "worker": "ok"},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    app.state.records = RecordRuntime(service, lambda: storage)
    with TestClient(app) as client:
        client.headers["Authorization"] = ids.authorization
        yield SimpleNamespace(
            client=client,
            sessions=sessions,
            service=service,
            storage=storage,
            ids=ids,
            app=app,
            jobs=PhotoJobs(sessions),
        )
    engine.dispose()


def observation_payload(ids):
    return {
        "mutation_id": str(uuid4()),
        "observation_id": str(uuid4()),
        "section_id": str(ids.section),
        "type": "health",
        "note": "Checked leaves",
        "created_at": datetime.now(timezone(timedelta(hours=2))).isoformat(),
    }


def upload_payload(records):
    return {
        "mutation_id": str(uuid4()),
        "local_media_id": str(uuid4()),
        "section_id": str(records.ids.section),
        "content_type": "image/png",
        "byte_length": len(records.storage.data),
    }


def reserve(records):
    payload = UploadCreate(**upload_payload(records))
    view, upload, attempt = records.service.reserve(
        records.ids.authorization, records.ids.farm, payload
    )
    return payload, view, upload, attempt


def queue(records):
    payload, view, upload, attempt = reserve(records)
    records.service.upload(records.ids.authorization, records.ids.farm, upload.id, complete=True)
    return payload, view, upload, attempt


def process(records, claimed=None):
    worker = PhotoWorker(records.sessions, lambda: records.storage)
    try:
        worker.process(*(claimed or records.jobs.claim(records.jobs.candidates()[0])))
    finally:
        worker.executor.shutdown()


@pytest.mark.parametrize(
    "header",
    ["", "Bearer invalid", "Bearer " + "z" * 43, "Bearer " + "a" * 64, "Basic " + "a" * 43],
)
def test_invalid_tokens_are_indistinguishable(records, header):
    response = records.client.get("/farms", headers={"Authorization": header})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "invalid_session"
    assert response.headers["www-authenticate"] == "Bearer"
    assert response.headers["x-request-id"]


@pytest.mark.parametrize("change", ["expired", "revoked", "unverified", "refresh"])
def test_session_and_identity_checks(records, change):
    with records.sessions.begin() as session:
        auth = session.scalar(select(AuthSession))
        if change == "expired":
            auth.expires_at = datetime.now(UTC) - timedelta(minutes=1)
        elif change == "revoked":
            auth.revoked_at = datetime.now(UTC)
        elif change == "unverified":
            session.get(AuthIdentity, records.ids.owner).email_verified = False
        else:
            auth.refresh_token_hash, auth.access_token_hash = auth.access_token_hash, "b" * 64
    assert records.client.get("/farms").status_code == 401


def test_scoped_reads_and_keyset_pagination(records):
    first = records.client.get("/farms?limit=1").json()
    second = records.client.get(f"/farms?limit=1&cursor={first['next_cursor']}").json()
    assert {first["items"][0]["id"], second["items"][0]["id"]} == {
        str(records.ids.farm),
        str(records.ids.second),
    }
    assert second["next_cursor"] is None
    assert records.client.get("/farms?limit=101").status_code == 422
    assert records.client.get("/farms?cursor=invalid").status_code == 422
    assert records.client.get(f"/farms/{records.ids.foreign}/sections").status_code == 404
    assert records.client.get(f"/farms/{records.ids.farm}/sections").json()["items"][0][
        "id"
    ] == str(records.ids.section)


def test_observation_replay_conflict_and_get(records):
    payload = observation_payload(records.ids)
    path = f"/farms/{records.ids.farm}/observations"
    first = records.client.post(path, json=payload)
    assert first.status_code == 200, first.text
    payload["created_at"] = (
        datetime.fromisoformat(payload["created_at"]).astimezone(UTC).isoformat()
    )
    replay = records.client.post(path, json=payload)
    assert replay.json() == first.json()
    payload["note"] = "Changed"
    assert records.client.post(path, json=payload).status_code == 409
    assert records.client.get(f"{path}/{payload['observation_id']}").status_code == 200
    assert len(records.client.get(path).json()["items"]) == 1
    with records.sessions() as session:
        for model in (Observation, SyncMutation, SyncChange):
            assert session.scalar(select(func.count()).select_from(model)) == 1


@pytest.mark.parametrize(
    "field,value",
    [
        ("owner_id", str(uuid4())),
        ("note", " "),
        ("created_by_voice", "true"),
        ("created_at", "2026-09-21T06:00:00"),
        ("type", "x" * 101),
    ],
)
def test_strict_observation_validation(records, field, value):
    payload = observation_payload(records.ids)
    payload[field] = value
    assert (
        records.client.post(f"/farms/{records.ids.farm}/observations", json=payload).status_code
        == 422
    )


@pytest.mark.parametrize("scope", ["foreign_section", "second_section"])
def test_cross_scope_observation_and_photo_rejected(records, scope):
    payload = observation_payload(records.ids)
    payload["section_id"] = str(getattr(records.ids, scope))
    assert (
        records.client.post(f"/farms/{records.ids.farm}/observations", json=payload).status_code
        == 404
    )
    photo = upload_payload(records)
    photo["section_id"] = payload["section_id"]
    assert (
        records.client.post(f"/farms/{records.ids.farm}/photo-uploads", json=photo).status_code
        == 404
    )


def test_deleted_scope_cannot_replay(records):
    payload = observation_payload(records.ids)
    path = f"/farms/{records.ids.farm}/observations"
    assert records.client.post(path, json=payload).status_code == 200
    with records.sessions.begin() as session:
        session.get(Section, records.ids.section).deleted_at = datetime.now(UTC)
    assert records.client.post(path, json=payload).status_code == 404
    assert records.client.get(path).json()["items"] == []


def test_body_limit_unknown_length_and_completion_descriptor(records):
    path = f"/farms/{records.ids.farm}/observations"
    response = records.client.post(path, content=iter([b"x" * 32768, b"x" * 32769]))
    assert response.status_code == 413
    assert response.headers["x-request-id"]
    _payload, _view, upload, _attempt = reserve(records)
    response = records.client.post(
        f"/farms/{records.ids.farm}/photo-uploads/{upload.id}/complete",
        json={"key": "another-owner"},
    )
    assert response.status_code == 422


def test_photo_flow_waits_for_validation_and_has_one_publication(records):
    payload = upload_payload(records)
    base = f"/farms/{records.ids.farm}"
    first = records.client.post(f"{base}/photo-uploads", json=payload)
    assert first.status_code == 200, first.text
    assert first.headers["cache-control"] == "no-store"
    assert "cloud_media_id" not in first.json()
    replay = records.client.post(f"{base}/photo-uploads", json=payload).json()
    assert {key: value for key, value in replay.items() if key != "form"} == {
        key: value for key, value in first.json().items() if key != "form"
    }
    assert datetime.fromisoformat(replay["form"]["expires_at"]) >= datetime.fromisoformat(
        first.json()["form"]["expires_at"]
    )
    path = f"{base}/photo-uploads/{first.json()['upload_id']}"
    assert records.client.post(path + "/complete").status_code == 202
    assert records.client.post(path + "/complete").status_code == 202
    process(records)
    ready = records.client.get(path).json()
    assert ready["state"] == "ready"
    assert records.client.post(path + "/complete").json() == ready
    observation = observation_payload(records.ids)
    observation["media_id"] = ready["cloud_media_id"]
    assert records.client.post(base + "/observations", json=observation).status_code == 200
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(Media)) == 1
        assert session.scalar(select(func.count()).select_from(SyncChange)) == 2


def test_reservation_conflicts_and_mutation_namespace(records):
    payload, _view, upload, _attempt = reserve(records)
    with pytest.raises(ApiError) as conflict:
        records.service.reserve(
            records.ids.authorization,
            records.ids.farm,
            payload.model_copy(update={"byte_length": payload.byte_length + 1}),
        )
    assert conflict.value.status == 409
    observation = ObservationCreate(**observation_payload(records.ids)).model_copy(
        update={"mutation_id": payload.mutation_id}
    )
    response = records.client.post(
        f"/farms/{records.ids.farm}/observations", json=observation.model_dump(mode="json")
    )
    assert response.status_code == 409
    assert (
        records.client.get(f"/farms/{records.ids.second}/photo-uploads/{upload.id}").status_code
        == 404
    )


def test_unvalidated_legacy_media_is_not_attachable(records):
    with records.sessions.begin() as session:
        media = Media(
            owner_id=records.ids.owner,
            farm_id=records.ids.farm,
            section_id=records.ids.section,
            local_id=str(uuid4()),
            media_type="image/png",
        )
        session.add(media)
        session.flush()
        media_id = str(media.id)
    payload = observation_payload(records.ids)
    payload["media_id"] = media_id
    assert (
        records.client.post(f"/farms/{records.ids.farm}/observations", json=payload).status_code
        == 404
    )


def test_older_transaction_cannot_shorten_issued_credential_lifetime(records, monkeypatch):
    payload, _view, upload, attempt = reserve(records)
    original_form_expiry = utc(attempt.form_expires_at)
    original_deadline = utc(attempt.expires_at)
    older_start = original_form_expiry - timedelta(minutes=5, seconds=10)
    monkeypatch.setattr("farmable_backend.records_service.db_now", lambda _: older_start)

    _view, replay, renewed = records.service.reserve(
        records.ids.authorization, records.ids.farm, payload
    )

    assert replay.id == upload.id and renewed.id == attempt.id
    with records.sessions() as session:
        persisted = session.get(PhotoAttempt, attempt.id)
        assert utc(persisted.form_expires_at) == original_form_expiry
        assert utc(persisted.expires_at) == original_deadline


def test_expired_upload_reopens_with_new_key_and_same_logical_identity(records):
    payload, _view, upload, attempt = reserve(records)
    with records.sessions.begin() as session:
        session.get(PhotoAttempt, attempt.id).expires_at = datetime.now(UTC) - timedelta(hours=2)
    view, replay, renewed = records.service.reserve(
        records.ids.authorization, records.ids.farm, payload
    )
    assert replay.id == upload.id and replay.media_id == upload.media_id
    assert renewed.id != attempt.id and view.state == "awaiting_upload"
    with pytest.raises(ApiError):
        records.service.upload(
            records.ids.authorization, records.ids.farm, upload.id, expected_attempt=attempt.id
        )


def test_failed_photo_is_terminal_and_budget_cannot_be_reset(records):
    payload, _view, upload, _attempt = queue(records)
    records.storage.failure = "invalid_photo"
    process(records)
    view, _upload, attempt = records.service.reserve(
        records.ids.authorization, records.ids.farm, payload
    )
    assert view.state == "failed" and attempt.attempt_count == 1
    assert view.cloud_media_id is None
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(Media)) == 0


def test_expired_lease_fences_stale_worker_and_claim_budget(records):
    _payload, _view, upload, _attempt = queue(records)
    first = records.jobs.claim(upload.id)
    assert records.jobs.claim(upload.id) is None
    with records.sessions.begin() as session:
        session.get(PhotoAttempt, first[1].id).lease_expires_at = datetime.now(UTC) - timedelta(
            seconds=1
        )
    second = records.jobs.claim(upload.id)
    assert second[1].lease_token != first[1].lease_token
    assert records.jobs.renew(upload.id, first[1].lease_token) is False
    process(records, first)
    process(records, second)
    assert (
        records.service.upload(records.ids.authorization, records.ids.farm, upload.id).state
        == "ready"
    )


def test_crash_after_cloud_write_recovers_pinned_version(records, monkeypatch):
    _payload, _view, upload, _attempt = queue(records)
    worker = PhotoWorker(records.sessions, lambda: records.storage)
    claimed = worker.jobs.claim(upload.id)
    original = worker.jobs.finish
    monkeypatch.setattr(
        worker.jobs, "finish", lambda *args: (_ for _ in ()).throw(RuntimeError("lost DB"))
    )
    worker.process(*claimed)
    monkeypatch.setattr(worker.jobs, "finish", original)
    records.storage.generation = "2"
    with records.sessions.begin() as session:
        session.get(PhotoAttempt, claimed[1].id).lease_expires_at = datetime.now(UTC) - timedelta(
            seconds=1
        )
    worker.process(*worker.jobs.claim(upload.id))
    worker.executor.shutdown()
    assert records.storage.read_generations == ["1", "1"]
    assert len(records.storage.published) == 1
    assert (
        records.service.upload(records.ids.authorization, records.ids.farm, upload.id).state
        == "ready"
    )


def test_retry_budget_and_cleanup_preserve_ready_objects(records):
    _payload, _view, upload, attempt = queue(records)
    records.storage.failure = "storage_unavailable"
    for _ in range(4):
        process(records, records.jobs.claim(upload.id))
        with records.sessions.begin() as session:
            session.get(PhotoAttempt, attempt.id).next_attempt_at = datetime.now(UTC) - timedelta(
                seconds=1
            )
    assert records.jobs.claim(upload.id) is None
    assert (
        records.service.upload(records.ids.authorization, records.ids.farm, upload.id).state
        == "failed"
    )
    records.storage.failure = None
    _payload, _view, ready_upload, ready_attempt = queue(records)
    process(records)
    with records.sessions.begin() as session:
        for attempt_id in (attempt.id, ready_attempt.id):
            row = session.get(PhotoAttempt, attempt_id)
            row.terminal_at = datetime.now(UTC) - timedelta(hours=2)
            row.form_expires_at = datetime.now(UTC) - timedelta(hours=2)
    worker = PhotoWorker(records.sessions, lambda: records.storage)
    worker.clean_batch()
    worker.executor.shutdown()
    assert (ready_upload.id, ready_attempt.id, True) in records.storage.cleaned
    assert (upload.id, attempt.id, False) in records.storage.cleaned


def test_photo_rate_is_shared_and_polling_is_free(records):
    _payload, _view, upload, _attempt = reserve(records)
    other = RecordsService(records.sessions)
    for _ in range(29):
        other.photo_rate(records.ids.authorization)
    with pytest.raises(ApiError) as limited:
        records.service.photo_rate(records.ids.authorization)
    assert limited.value.status == 429 and limited.value.retry_after > 0
    assert (
        records.service.upload(records.ids.authorization, records.ids.farm, upload.id).state
        == "awaiting_upload"
    )


def test_storage_disabled_does_not_block_photo_free_writes(records):
    records.app.state.records.storage_factory = lambda: None
    response = records.client.post(
        f"/farms/{records.ids.farm}/photo-uploads", json=upload_payload(records)
    )
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "photo_storage_disabled"
    response = records.client.post(
        f"/farms/{records.ids.farm}/observations", json=observation_payload(records.ids)
    )
    assert response.status_code == 200


def test_cancelled_request_does_not_free_occupied_executor_slot(records):
    runtime = records.app.state.records
    started = threading.Event()
    release = threading.Event()

    def held():
        started.set()
        assert release.wait(timeout=15)

    async def exercise():
        first = asyncio.create_task(runtime.call(held))
        await asyncio.to_thread(started.wait, 5)
        assert started.is_set()
        first.cancel()
        with pytest.raises(asyncio.CancelledError):
            await first
        others = [asyncio.create_task(runtime.call(held)) for _ in range(7)]
        try:
            await asyncio.sleep(0)
            with pytest.raises(ApiError) as overloaded:
                await runtime.call(lambda: None)
            assert overloaded.value.status == 503
        finally:
            release.set()
            await asyncio.gather(*others)

    asyncio.run(exercise())


def test_database_contention_maps_to_retryable_safe_error(records):
    from sqlalchemy.exc import OperationalError

    def unavailable():
        raise OperationalError("sensitive-query", {}, RuntimeError("private-connection-details"))

    with pytest.raises(ApiError) as error:
        asyncio.run(records.app.state.records.call(unavailable))
    assert error.value.status == 503 and error.value.retry_after == 5
    assert "private" not in str(error.value)


def test_sensitive_photo_values_are_not_logged(records, caplog):
    response = records.client.post(
        f"/farms/{records.ids.farm}/photo-uploads", json=upload_payload(records)
    )
    assert response.status_code == 200
    assert "secret-form" not in caplog.text
    assert records.ids.authorization not in caplog.text
    assert "storage.example.test" not in caplog.text


def test_corrupt_bytes_and_revoked_ready_media_are_rejected(records):
    records.storage.data = b"not really a png"
    _payload, _view, upload, _attempt = queue(records)
    process(records)
    assert (
        records.service.upload(records.ids.authorization, records.ids.farm, upload.id).state
        == "failed"
    )
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(Media)) == 0


def test_openapi_declares_bearer_and_error_contract(records):
    schema = records.app.openapi()
    route = schema["paths"]["/farms/{farm_id}/observations"]["post"]
    assert route["security"] == [{"SessionBearer": []}]
    assert "ErrorResponse" in str(route["responses"]["401"])
