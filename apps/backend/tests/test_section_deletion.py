"""Terminal section erasure must preserve sync receipts, not dependent data."""

from datetime import UTC, datetime, timedelta
from uuid import UUID, uuid4

import pytest
from farmable_backend.models import (
    CropDiagnosis,
    Media,
    PhotoAttempt,
    PhotoUpload,
    PlanRevision,
    Planting,
    Section,
    SectionDeletion,
)
from farmable_backend.photo_worker import PhotoWorker
from farmable_backend.records_schemas import RecordDelete
from farmable_backend.section_deletion import SectionDeletionJobs
from farmable_backend.sync_records import SECTION_ATTACHED
from sqlalchemy import func, select
from test_records_api import observation_payload, process, queue

pytest_plugins = ("test_records_api",)


def delete_section(records, *, photo=True):
    from test_sync_api import create_body

    children = {}
    for resource in ("plantings", "tasks", "financials", "plans", "media"):
        body = create_body(records, resource)
        response = records.client.post(f"/farms/{records.ids.farm}/{resource}", json=body)
        assert response.status_code == 200, response.text
        children[resource] = UUID(body["id"])
    body = observation_payload(records.ids)
    response = records.client.post(f"/farms/{records.ids.farm}/observations", json=body)
    assert response.status_code == 200, response.text
    children["observations"] = UUID(body["observation_id"])
    versions = dict.fromkeys(children.values(), 1)
    attempt_id = None
    if photo:
        _, _, upload, attempt = queue(records)
        process(records)
        attempt_id = attempt.id
        versions[upload.media_id] = 1
        records.storage.incoming[attempt.id] = b"late upload"
        with records.sessions.begin() as session:
            for state in ("queued", "processing", "ready", "unavailable", "cancelled"):
                session.add(
                    CropDiagnosis(
                        id=uuid4(),
                        owner_id=records.ids.owner,
                        farm_id=records.ids.farm,
                        section_id=records.ids.section,
                        media_id=upload.media_id,
                        planting_id=children["plantings"],
                        planting_version=1,
                        crop="cabbage",
                        fingerprint="test",
                        consent_notice_version="crop-health-v1",
                        state=state,
                        next_attempt_at=datetime.now(UTC),
                        result={"private": "scan output"},
                    )
                )
    payload = RecordDelete(
        mutation_id=uuid4(), expected_version=1, expected_child_versions=versions
    )
    ack = records.service.mutate(
        records.ids.authorization,
        records.ids.farm,
        "sections",
        "delete",
        records.ids.section,
        payload,
    )
    return children, attempt_id, payload, ack


def clean(records):
    worker = PhotoWorker(records.sessions, lambda: records.storage)
    try:
        worker.clean_batch()
    finally:
        worker.executor.shutdown()


def assert_erased(records):
    with records.sessions() as session:
        for model in (
            *(kind.model for kind in SECTION_ATTACHED),
            CropDiagnosis,
            PhotoUpload,
            PlanRevision,
        ):
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(model)
                    .where(model.section_id == records.ids.section)
                )
                == 0
            ), model.__tablename__
        assert session.scalar(select(func.count()).select_from(PhotoAttempt)) == 0
        assert session.get(Section, records.ids.section).deleted_at is not None
    assert not records.storage.incoming
    assert not records.storage.published


def test_section_deletion_finishes_database_and_storage_cleanup(records, monkeypatch):
    children, attempt_id, payload, ack = delete_section(records)
    changes = records.service.changes(records.ids.authorization, records.ids.farm, 0, 100)
    clean(records)
    with records.sessions() as session:
        assert session.get(PhotoAttempt, attempt_id) is not None
        assert session.get(Planting, children["plantings"]) is not None
    # Advance the shared database clock, never shorten real signed-form/lease deadlines.
    later = datetime.now(UTC) + timedelta(hours=2)
    monkeypatch.setattr("farmable_backend.photo_jobs.db_now", lambda _: later)
    monkeypatch.setattr("farmable_backend.record_access.db_now", lambda _: later)
    clean(records)
    assert_erased(records)
    clean(records)  # Restart/repeat is harmless, and offline delete receipts survive.
    assert_erased(records)
    assert records.service.changes(records.ids.authorization, records.ids.farm, 0, 100) == changes
    replay = records.service.mutate(
        records.ids.authorization,
        records.ids.farm,
        "sections",
        "delete",
        records.ids.section,
        payload,
    )
    assert replay == ack


def test_section_without_files_is_erased_without_storage(records):
    delete_section(records, photo=False)
    worker = PhotoWorker(records.sessions, lambda: None)
    try:
        worker.clean_batch()
    finally:
        worker.executor.shutdown()
    assert_erased(records)


def test_deleted_sections_from_before_the_job_upgrade_are_recovered(records, monkeypatch):
    delete_section(records)
    with records.sessions.begin() as session:
        session.delete(session.get(SectionDeletion, records.ids.section))
        upload = session.scalar(select(PhotoUpload))
        upload.state = "ready"
        attempt = session.scalar(select(PhotoAttempt))
        attempt.cleaned_at = datetime.now(UTC)
    now = datetime.now(UTC)
    monkeypatch.setattr("farmable_backend.record_access.db_now", lambda _: now)
    clean(records)
    assert records.storage.published  # Upgrade must restart the write-safety window.
    now += timedelta(hours=2)
    clean(records)
    assert_erased(records)


@pytest.mark.parametrize("resource", ["plantings", "observations"])
def test_erased_record_id_cannot_be_recreated_by_a_fresh_mutation(records, resource):
    children, _, _, _ = delete_section(records, photo=False)
    clean(records)
    section_id = uuid4()
    base = f"/farms/{records.ids.farm}"
    assert (
        records.client.post(
            base + "/sections",
            json={
                "id": str(section_id),
                "mutation_id": str(uuid4()),
                "name": "New plot",
            },
        ).status_code
        == 200
    )
    body = {
        "id": str(children[resource]),
        "mutation_id": str(uuid4()),
        "section_id": str(section_id),
        "crop": "cabbage",
    }
    if resource == "observations":
        body = observation_payload(records.ids)
        body.update(observation_id=str(children[resource]), section_id=str(section_id))
    response = records.client.post(base + "/" + resource, json=body)
    assert response.status_code == 409


def test_storage_failure_has_three_retries_and_preserves_the_cleanup_manifest(records, monkeypatch):
    delete_section(records)
    now = datetime.now(UTC) + timedelta(hours=2)
    monkeypatch.setattr("farmable_backend.record_access.db_now", lambda _: now)
    calls = []

    def unavailable(*args, **kwargs):
        calls.append(True)
        raise OSError("synthetic storage outage")

    monkeypatch.setattr(records.storage, "cleanup", unavailable)
    for count in range(1, 5):
        clean(records)  # New worker each time: retry state must survive process restarts.
        with records.sessions() as session:
            job = session.get(SectionDeletion, records.ids.section)
            assert job.failures == count
            assert job.status == ("failed" if count == 4 else "pending")
            assert job.completed_at is None
            assert session.scalar(select(PhotoAttempt)).cleaned_at is None
            assert session.scalar(select(PhotoUpload)) is not None
        clean(records)  # Backoff is enforced.
        assert len(calls) == count
        now += timedelta(hours=1)
    clean(records)
    assert len(calls) == 4
    assert records.storage.published


def test_expired_cleanup_lease_is_recovered_and_stale_worker_cannot_finish(records, monkeypatch):
    delete_section(records, photo=False)
    now = datetime.now(UTC)
    monkeypatch.setattr("farmable_backend.record_access.db_now", lambda _: now)
    jobs = SectionDeletionJobs(records.sessions)
    first = jobs.claim(records.ids.section)
    assert first is not None
    assert SectionDeletionJobs(records.sessions).claim(records.ids.section) is None
    now += timedelta(minutes=6)
    assert jobs.claim(records.ids.section) is None  # Counts the lost worker, then backs off.
    now += timedelta(seconds=11)
    second = SectionDeletionJobs(records.sessions).claim(records.ids.section)
    assert second is not None and second != first
    assert not jobs.finish(records.ids.section, first)
    assert jobs.finish(records.ids.section, second)
    assert_erased(records)


def test_section_cleanup_keeps_other_sections_and_delete_receipts(records):
    with records.sessions.begin() as session:
        survivor = Planting(
            id=uuid4(),
            owner_id=records.ids.owner,
            farm_id=records.ids.second,
            section_id=records.ids.second_section,
            crop="tomato",
        )
        session.add(survivor)
    delete_section(records, photo=False)
    clean(records)
    with records.sessions() as session:
        assert session.get(Planting, survivor.id).deleted_at is None
        assert session.get(SectionDeletion, records.ids.section).status == "complete"


def test_partial_storage_batch_resumes_without_spending_a_failure_retry(records, monkeypatch):
    delete_section(records)
    later = datetime.now(UTC) + timedelta(hours=2)
    monkeypatch.setattr("farmable_backend.record_access.db_now", lambda _: later)
    original = records.storage.cleanup

    def first_page(upload, attempt, **kwargs):
        records.storage.incoming.pop(attempt.id, None)
        monkeypatch.setattr(records.storage, "cleanup", original)
        return False

    monkeypatch.setattr(records.storage, "cleanup", first_page)
    clean(records)
    with records.sessions() as session:
        job = session.get(SectionDeletion, records.ids.section)
        assert job.status == "pending" and job.failures == 0
        assert session.scalar(select(PhotoAttempt)).cleaned_at is None
    clean(records)
    assert_erased(records)


def test_missing_storage_manifest_cannot_be_reported_as_complete(records, monkeypatch):
    delete_section(records, photo=False)
    with records.sessions.begin() as session:
        media = session.scalar(select(Media))
        media.object_key = "legacy-object-without-an-upload-manifest"
    now = datetime.now(UTC)
    monkeypatch.setattr("farmable_backend.record_access.db_now", lambda _: now)
    for _ in range(4):
        clean(records)
        now += timedelta(hours=1)
    with records.sessions() as session:
        assert session.get(SectionDeletion, records.ids.section).status == "failed"
        assert session.scalar(select(Media)).object_key is not None


def test_revision_conflict_never_commits_an_erasure_intent(records):
    from farmable_backend.record_access import ApiError
    from farmable_backend.records_schemas import PlantingCreate

    records.service.mutate(
        records.ids.authorization,
        records.ids.farm,
        "plantings",
        "create",
        None,
        PlantingCreate(
            id=uuid4(), mutation_id=uuid4(), section_id=records.ids.section, crop="cabbage"
        ),
    )
    with pytest.raises(ApiError, match="revision_conflict"):
        records.service.mutate(
            records.ids.authorization,
            records.ids.farm,
            "sections",
            "delete",
            records.ids.section,
            RecordDelete(mutation_id=uuid4(), expected_version=1),
        )
    with records.sessions() as session:
        assert session.get(SectionDeletion, records.ids.section) is None
        assert session.get(Section, records.ids.section).deleted_at is None
