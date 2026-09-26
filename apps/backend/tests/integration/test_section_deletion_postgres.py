"""Create/move versus delete under real PostgreSQL READ COMMITTED locks."""

import time
from concurrent.futures import ThreadPoolExecutor
from queue import Queue
from uuid import uuid4

import pytest
from alembic import command
from farmable_backend.models import Media, Planting, Section, SectionDeletion
from farmable_backend.record_access import ApiError
from farmable_backend.records_schemas import MediaUpdate, PlantingCreate, RecordDelete
from farmable_backend.section_deletion import SectionDeletionJobs
from farmable_backend.sync_records import SyncRecordRepository
from sqlalchemy import func, select
from test_section_deletion import assert_erased, clean, delete_section

pytestmark = pytest.mark.integration
pytest_plugins = ("test_photo_sync_postgres",)


@pytest.mark.parametrize("move", [False, True], ids=["create", "move"])
def test_farm_records_create_or_move_cannot_escape_section_deletion(pg, move):
    command.upgrade(pg.config, "head")
    child_id = uuid4()
    if move:
        with pg.sessions.begin() as session:
            origin = Section(id=uuid4(), owner_id=pg.ids.owner, farm_id=pg.ids.farm, name="Keep")
            session.add(origin)
            session.flush()
            session.add(
                Media(
                    id=child_id,
                    owner_id=pg.ids.owner,
                    farm_id=pg.ids.farm,
                    section_id=origin.id,
                    local_id="move",
                    media_type="image/png",
                )
            )
    started = Queue()

    def create_or_move():
        try:
            with pg.sessions.begin() as session:
                started.put(session.scalar(select(func.pg_backend_pid())))
                payload = (
                    MediaUpdate(
                        mutation_id=uuid4(),
                        expected_version=1,
                        section_id=pg.ids.section,
                        media_type="image/png",
                    )
                    if move
                    else PlantingCreate(
                        id=child_id, mutation_id=uuid4(), section_id=pg.ids.section, crop="cabbage"
                    )
                )
                SyncRecordRepository(session, pg.ids.owner, pg.ids.farm).apply(
                    resource="media" if move else "plantings",
                    operation="update" if move else "create",
                    record_id=child_id if move else None,
                    payload=payload,
                )
            return "committed"
        except ApiError as error:
            return error.code

    with ThreadPoolExecutor(max_workers=1) as pool:
        with pg.sessions.begin() as session:
            blocker = session.scalar(select(func.pg_backend_pid()))
            SyncRecordRepository(session, pg.ids.owner, pg.ids.farm).apply(
                resource="sections",
                operation="delete",
                record_id=pg.ids.section,
                payload=RecordDelete(mutation_id=uuid4(), expected_version=1),
            )
            future = pool.submit(create_or_move)
            pid = started.get(timeout=5)
            deadline = time.monotonic() + 3
            blocked = False
            while time.monotonic() < deadline and not future.done():
                with pg.sessions() as observer:
                    if blocker in observer.scalar(select(func.pg_blocking_pids(pid))):
                        blocked = True
                        break
                time.sleep(0.01)
            assert blocked, "The concurrent transaction must actually overlap the deletion"
        assert future.result(timeout=5) == "not_found"
    with pg.sessions() as session:
        for model in (Planting, Media):
            assert (
                session.scalar(
                    select(func.count())
                    .select_from(model)
                    .where(model.section_id == pg.ids.section, model.deleted_at.is_(None))
                )
                == 0
            )


def test_farm_records_terminal_section_cleanup_matches_real_foreign_keys(pg, monkeypatch):
    from datetime import UTC, datetime, timedelta

    # Reuse the public service through a tiny HTTP-shaped adapter for shared fixtures.
    from types import SimpleNamespace

    from farmable_backend.records_schemas import (
        FinancialCreate,
        MediaCreate,
        ObservationCreate,
        PlanCreate,
        PlantingCreate,
        TaskCreate,
    )

    command.upgrade(pg.config, "head")
    models = {
        "financials": FinancialCreate,
        "media": MediaCreate,
        "plans": PlanCreate,
        "plantings": PlantingCreate,
        "tasks": TaskCreate,
    }

    def post(path, *, json):
        resource = path.rsplit("/", 1)[-1]
        if resource == "observations":
            pg.service.observe(pg.ids.authorization, pg.ids.farm, ObservationCreate(**json))
        else:
            pg.service.mutate(
                pg.ids.authorization,
                pg.ids.farm,
                resource,
                "create",
                None,
                models[resource](**json),
            )
        return SimpleNamespace(status_code=200, text="")

    pg.client = SimpleNamespace(post=post)
    delete_section(pg)
    later = datetime.now(UTC) + timedelta(hours=2)
    monkeypatch.setattr("farmable_backend.record_access.db_now", lambda _: later)
    clean(pg)
    assert_erased(pg)


def test_farm_records_cleanup_job_has_one_owner_across_replicas(pg):
    from test_photo_sync_postgres import race

    command.upgrade(pg.config, "head")
    pg.service.mutate(
        pg.ids.authorization,
        pg.ids.farm,
        "sections",
        "delete",
        pg.ids.section,
        RecordDelete(mutation_id=uuid4(), expected_version=1),
    )
    tokens = race(lambda: SectionDeletionJobs(pg.sessions).claim(pg.ids.section), count=2)
    assert sum(token is not None for token in tokens) == 1
    token = next(token for token in tokens if token is not None)
    assert SectionDeletionJobs(pg.sessions).finish(pg.ids.section, token)
    assert not SectionDeletionJobs(pg.sessions).finish(pg.ids.section, token)
    with pg.sessions() as session:
        assert session.get(SectionDeletion, pg.ids.section).status == "complete"
    clean(pg)
    assert_erased(pg)
