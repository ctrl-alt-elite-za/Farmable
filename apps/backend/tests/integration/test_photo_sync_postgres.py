"""Real PostgreSQL races and additive migration, confined to random CI schemas."""

import asyncio
import os
from concurrent.futures import ThreadPoolExecutor
from datetime import UTC, datetime, timedelta
from threading import Barrier
from types import SimpleNamespace
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from alembic.migration import MigrationContext
from farmable_backend import database
from farmable_backend.config import Settings
from farmable_backend.models import (
    Farm,
    Media,
    Observation,
    PhotoAttempt,
    PhotoUpload,
    SyncChange,
    SyncMutation,
    User,
)
from farmable_backend.photo_jobs import PhotoJobs
from farmable_backend.photo_policy import MAX_CLAIMS
from farmable_backend.photo_worker import PhotoWorker
from farmable_backend.record_access import ApiError
from farmable_backend.records_schemas import ObservationCreate, UploadCreate
from farmable_backend.records_service import RecordsService
from sqlalchemy import create_engine, func, inspect, select, update
from sqlalchemy.exc import IntegrityError, OperationalError
from sqlalchemy.orm import sessionmaker
from sqlalchemy.schema import CreateSchema, DropSchema
from test_records_api import FakeStorage, observation_payload, seed

pytestmark = pytest.mark.integration


@pytest.fixture
def pg(monkeypatch):
    assert os.environ.get("ENVIRONMENT") == "ci", "Use only the disposable integration harness"
    schema = "photo_sync_" + uuid4().hex
    admin = database.make_engine(Settings())
    engine = create_engine(
        Settings().database_url.get_secret_value(),
        connect_args={
            "connect_timeout": 5,
            "options": (f"-c statement_timeout=5000 -c search_path={schema},public"),
        },
        hide_parameters=True,
    )
    migration_engine = create_engine(
        Settings().database_url.get_secret_value(),
        connect_args={
            "connect_timeout": 5,
            "options": (
                f"-c statement_timeout=5000 -c lock_timeout=1000 -c search_path={schema},public"
            ),
        },
        hide_parameters=True,
    )
    try:
        with admin.begin() as connection:
            connection.execute(CreateSchema(schema))

        def migrate_engine(settings, *, migration=False):
            assert migration, "Migration-only lock timeout must not leak into runtime sessions"
            return migration_engine

        monkeypatch.setattr(database, "make_engine", migrate_engine)
        config = Config("alembic.ini")
        config.attributes["version_table_schema"] = schema
        command.upgrade(config, "0004")
        sessions = sessionmaker(engine, expire_on_commit=False)
        ids = seed(sessions)
        yield SimpleNamespace(
            engine=engine,
            migration_engine=migration_engine,
            config=config,
            schema=schema,
            sessions=sessions,
            ids=ids,
            service=RecordsService(sessions),
            jobs=PhotoJobs(sessions),
            storage=FakeStorage(),
        )
    finally:
        engine.dispose()
        migration_engine.dispose()
        with admin.begin() as connection:
            connection.execute(DropSchema(schema, cascade=True, if_exists=True))
        admin.dispose()


def photo_input(pg):
    return UploadCreate(
        mutation_id=uuid4(),
        local_media_id=uuid4(),
        section_id=pg.ids.section,
        content_type="image/png",
        byte_length=len(pg.storage.data),
    )


def test_populated_upgrade_preserves_rows_and_matches_metadata(pg):
    with pg.sessions() as session:
        before = list(session.execute(select(Farm.id, Farm.owner_id, Farm.name, Farm.updated_at)))
        users = list(session.scalars(select(User.id)))
    command.upgrade(pg.config, "0005")
    with pg.sessions() as session:
        assert (
            list(session.execute(select(Farm.id, Farm.owner_id, Farm.name, Farm.updated_at)))
            == before
        )
        assert list(session.scalars(select(User.id))) == users
        assert session.scalar(select(func.count()).select_from(PhotoUpload)) == 0
        assert session.scalar(select(func.current_setting("statement_timeout"))) == "5s"
    with pg.migration_engine.connect() as connection:
        assert connection.scalar(select(func.current_setting("lock_timeout"))) == "1s"
    assert {"photo_uploads", "photo_attempts", "photo_rates"} <= set(
        inspect(pg.engine).get_table_names(schema=pg.schema)
    )


def test_migration_metadata_lock_is_bounded_and_atomic(pg):
    with pg.engine.connect() as blocker:
        transaction = blocker.begin()
        blocker.execute(update(User).where(User.id == pg.ids.owner).values(updated_at=func.now()))
        try:
            with pytest.raises(OperationalError) as failure:
                command.upgrade(pg.config, "0005")
            assert failure.value.orig.sqlstate == "55P03"
        finally:
            transaction.rollback()
    with pg.engine.connect() as connection:
        context = MigrationContext.configure(connection, opts={"version_table_schema": pg.schema})
        assert context.get_current_revision() == "0004"
    assert "photo_uploads" not in inspect(pg.engine).get_table_names(schema=pg.schema)
    command.upgrade(pg.config, "0005")


def race(function, count=8):
    barrier = Barrier(count)

    def run(_):
        barrier.wait(timeout=10)
        return function()

    with ThreadPoolExecutor(max_workers=count) as executor:
        return list(executor.map(run, range(count)))


def test_concurrent_observation_retries_have_one_committed_result(pg):
    command.upgrade(pg.config, "0005")
    payload = ObservationCreate(**observation_payload(pg.ids))
    results = race(lambda: pg.service.observe(pg.ids.authorization, pg.ids.farm, payload))
    assert all(item.model_dump() == results[0].model_dump() for item in results)
    with pg.sessions() as session:
        for model in (Observation, SyncMutation, SyncChange):
            assert session.scalar(select(func.count()).select_from(model)) == 1


def test_concurrent_reservations_completions_and_worker_claims(pg):
    command.upgrade(pg.config, "0005")
    payload = photo_input(pg)
    reservations = race(lambda: pg.service.reserve(pg.ids.authorization, pg.ids.farm, payload))
    upload_id = reservations[0][0].upload_id
    assert {item[0].upload_id for item in reservations} == {upload_id}
    completions = race(
        lambda: pg.service.upload(pg.ids.authorization, pg.ids.farm, upload_id, complete=True)
    )
    assert all(item.state == "queued" for item in completions)
    claims = race(lambda: pg.jobs.claim(upload_id))
    assert sum(item is not None for item in claims) == 1
    worker = PhotoWorker(pg.sessions, lambda: pg.storage)
    try:
        worker.process(*next(item for item in claims if item is not None))
    finally:
        worker.executor.shutdown()
    assert pg.service.upload(pg.ids.authorization, pg.ids.farm, upload_id).state == "ready"
    with pg.sessions() as session:
        for model in (Media, PhotoUpload, PhotoAttempt, SyncMutation, SyncChange):
            assert session.scalar(select(func.count()).select_from(model)) == 1


def test_owner_quota_serializes_across_service_instances(pg):
    command.upgrade(pg.config, "0005")
    for _ in range(29):
        pg.service.photo_rate(pg.ids.authorization)

    def admit():
        try:
            RecordsService(pg.sessions).photo_rate(pg.ids.authorization)
            return 200
        except ApiError as error:
            return error.status

    results = race(admit)
    assert results.count(200) == 1 and results.count(429) == 7


def test_worker_cannot_publish_after_section_deleted(pg):
    from farmable_backend.models import Section

    command.upgrade(pg.config, "0005")
    _view, upload, _attempt = pg.service.reserve(pg.ids.authorization, pg.ids.farm, photo_input(pg))
    pg.service.upload(pg.ids.authorization, pg.ids.farm, upload.id, complete=True)
    claim = pg.jobs.claim(upload.id)
    with pg.sessions.begin() as session:
        session.get(Section, pg.ids.section).deleted_at = datetime.now(UTC)
    worker = PhotoWorker(pg.sessions, lambda: pg.storage)
    try:
        worker.process(*claim)
    finally:
        worker.executor.shutdown()
    with pg.sessions() as session:
        assert session.get(PhotoUpload, upload.id).state == "failed"
        assert session.scalar(select(func.count()).select_from(Media)) == 0


def test_database_rejects_wrong_owner_upload_and_excessive_attempt_count(pg):
    command.upgrade(pg.config, "0005")
    _view, upload, attempt = pg.service.reserve(pg.ids.authorization, pg.ids.farm, photo_input(pg))
    with pytest.raises(IntegrityError), pg.sessions.begin() as session:
        session.get(PhotoUpload, upload.id).owner_id = pg.ids.other
    with pytest.raises(IntegrityError), pg.sessions.begin() as session:
        session.get(PhotoAttempt, attempt.id).attempt_count = 5


def test_cleanup_old_attempt_cannot_delete_renewed_upload(pg):
    command.upgrade(pg.config, "0005")
    payload = photo_input(pg)
    _view, upload, attempt = pg.service.reserve(pg.ids.authorization, pg.ids.farm, payload)
    with pg.sessions.begin() as session:
        row = session.get(PhotoAttempt, attempt.id)
        row.expires_at = datetime.now(UTC) - timedelta(hours=3)
        row.form_expires_at = row.expires_at
    cleanup = pg.jobs.cleanup_claim(upload.id, attempt.id)
    assert cleanup is not None
    _view, _upload, renewed = pg.service.reserve(pg.ids.authorization, pg.ids.farm, payload)
    assert renewed.id != attempt.id
    pg.storage.cleanup(cleanup[0], cleanup[1], keep_clean=False)
    pg.jobs.cleanup_finish(upload.id, attempt.id, cleanup[1].cleanup_token, True)
    with pg.sessions() as session:
        assert session.get(PhotoAttempt, renewed.id).cleaned_at is None
        assert session.get(PhotoUpload, upload.id).state == "awaiting_upload"


def test_worker_discovers_committed_intent_without_enqueue_or_client_resend(pg):
    command.upgrade(pg.config, "0005")
    _view, upload, _attempt = pg.service.reserve(pg.ids.authorization, pg.ids.farm, photo_input(pg))
    pg.service.upload(pg.ids.authorization, pg.ids.farm, upload.id, complete=True)
    worker = PhotoWorker(pg.sessions, lambda: pg.storage)

    async def exercise():
        task = asyncio.create_task(worker.run())
        try:

            async def ready():
                while True:
                    view = await asyncio.to_thread(
                        pg.service.upload, pg.ids.authorization, pg.ids.farm, upload.id
                    )
                    if view.state == "ready":
                        return
                    await asyncio.sleep(0.05)

            await asyncio.wait_for(ready(), timeout=15)
        finally:
            worker.stop.set()
            await task

    asyncio.run(exercise())


def test_concurrent_recovery_preserves_one_photo_and_stale_attempt_fences(pg):
    command.upgrade(pg.config, "0005")
    payload = photo_input(pg)
    _, upload, attempt = pg.service.reserve(pg.ids.authorization, pg.ids.farm, payload)
    pg.service.upload(pg.ids.authorization, pg.ids.farm, upload.id, complete=True)
    stale_claim = None
    for _ in range(MAX_CLAIMS):
        stale_claim = pg.jobs.claim(upload.id)
        pg.jobs.fail(upload.id, stale_claim[1].lease_token, "storage_unavailable", transient=True)
        with pg.sessions.begin() as session:
            session.get(PhotoAttempt, attempt.id).next_attempt_at = datetime.now(UTC) - timedelta(
                seconds=1
            )
    # A janitor already owns the old attempt before recovery. Its immutable keys
    # and stale worker token must remain harmless after a new attempt starts.
    with pg.sessions.begin() as session:
        old = session.get(PhotoAttempt, attempt.id)
        old.terminal_at = datetime.now(UTC) - timedelta(hours=2)
        old.form_expires_at = old.terminal_at
    cleanup = pg.jobs.cleanup_claim(upload.id, attempt.id)
    assert cleanup is not None
    recovered = race(
        lambda: pg.service.retry_upload(pg.ids.authorization, pg.ids.farm, upload.id, attempt.id)
    )
    assert {item.attempt_id for item in recovered} == {recovered[0].attempt_id}
    assert all(item.state == "awaiting_upload" for item in recovered)
    assert all(item.entity_id == payload.local_media_id for item in recovered)
    _, same_upload, renewed = pg.service.reserve(pg.ids.authorization, pg.ids.farm, payload)
    assert same_upload.media_id == upload.media_id and renewed.id != attempt.id
    pg.storage.cleanup(cleanup[0], cleanup[1], keep_clean=False)
    pg.jobs.cleanup_finish(upload.id, attempt.id, cleanup[1].cleanup_token, True)
    pg.service.upload(pg.ids.authorization, pg.ids.farm, upload.id, complete=True)
    worker = PhotoWorker(pg.sessions, lambda: pg.storage)
    try:
        worker.process(*stale_claim)
        claims = race(lambda: pg.jobs.claim(upload.id))
        assert sum(item is not None for item in claims) == 1
        worker.process(*next(item for item in claims if item is not None))
    finally:
        worker.executor.shutdown()
    ready = pg.service.upload(pg.ids.authorization, pg.ids.farm, upload.id)
    assert ready.state == "ready" and ready.cloud_media_id == upload.media_id
    assert (
        pg.service.retry_upload(pg.ids.authorization, pg.ids.farm, upload.id, attempt.id) == ready
    )
    with pg.sessions() as session:
        assert session.get(PhotoAttempt, renewed.id).cleaned_at is None
        assert session.scalar(select(func.count()).select_from(PhotoAttempt)) == 2
        for model in (PhotoUpload, SyncMutation, Media, SyncChange):
            assert session.scalar(select(func.count()).select_from(model)) == 1
