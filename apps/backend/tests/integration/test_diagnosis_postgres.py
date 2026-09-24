"""Diagnosis row-lock races on a disposable, fully migrated PostgreSQL schema."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier
from uuid import uuid4

import pytest
from alembic import command
from farmable_backend.diagnosis import DiagnosisStore
from farmable_backend.diagnosis_schemas import DiagnosisCreate
from farmable_backend.diagnosis_worker import normalized
from farmable_backend.models import CropDiagnosis, Planting
from sqlalchemy import event, func, select
from test_diagnosis import sample
from test_records_api import process, queue

pytestmark = pytest.mark.integration
pytest_plugins = ("test_photo_sync_postgres",)


def test_farm_records_diagnosis_replay_claim_and_cancel_across_replicas(pg):
    command.upgrade(pg.config, "head")
    _, _, upload, _ = queue(pg)
    process(pg)
    with pg.sessions.begin() as session:
        planting = Planting(
            id=uuid4(),
            owner_id=pg.ids.owner,
            farm_id=pg.ids.farm,
            section_id=pg.ids.section,
            crop="tomato",
        )
        session.add(planting)
    payload = DiagnosisCreate(
        id=uuid4(),
        media_id=upload.media_id,
        planting_id=planting.id,
        consent_notice_version="crop-health-v1",
    )

    def race(function):
        barrier = Barrier(2, timeout=10)

        def before_lock(conn, cursor, statement, params, context, many):
            if statement.startswith("SELECT farms.") and "FOR UPDATE" in statement:
                barrier.wait()

        event.listen(pg.engine, "before_cursor_execute", before_lock)
        try:
            with ThreadPoolExecutor(max_workers=2) as executor:
                return list(executor.map(function, range(2)))
        finally:
            event.remove(pg.engine, "before_cursor_execute", before_lock)

    results = race(
        lambda _: DiagnosisStore(pg.sessions).submit(
            pg.ids.authorization,
            pg.ids.farm,
            pg.ids.section,
            payload,
        )
    )
    assert results[0] == results[1]
    with pg.sessions() as session:
        assert session.scalar(select(func.count()).select_from(CropDiagnosis)) == 1
    claims = race(lambda _: DiagnosisStore(pg.sessions).claim(payload.id))
    assert sum(claim is not None for claim in claims) == 1
    row, _, _ = next(claim for claim in claims if claim is not None)
    assert row.attempts == 1
    DiagnosisStore(pg.sessions).read(pg.ids.authorization, pg.ids.farm, row.id, cancel=True)
    assert not DiagnosisStore(pg.sessions).finish(
        row.id,
        row.lease_token,
        result=normalized(sample(), "tomato", synthetic=True),
    )
    snapshot = DiagnosisStore(pg.sessions).read(pg.ids.authorization, pg.ids.farm, row.id)
    assert snapshot.state == "cancelled" and snapshot.result is None
