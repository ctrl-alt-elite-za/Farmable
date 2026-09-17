import ast
import asyncio
import os
import time
from pathlib import Path

import httpx
import pytest
from alembic import command
from alembic.config import Config
from farmable_backend.config import Settings
from farmable_backend.database import Database, QueueJob, make_engine
from farmable_backend.models import DetectorModel, WeightFormula
from farmable_backend.scripts.detector_model_exists import exists
from farmable_backend.tasks import create_task_app
from sqlalchemy import func, inspect, select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

pytestmark = pytest.mark.integration


def await_ready(database, worker, timeout=60):
    expected = {"database": database, "worker": worker, "sha": os.environ["COMMIT_SHA"]}
    deadline = time.monotonic() + timeout
    with httpx.Client(base_url=os.environ["API_URL"], timeout=15) as client:
        while time.monotonic() < deadline:
            try:
                response = client.get("/health/ready")
                if response.json() == expected:
                    assert response.status_code == (200 if database == worker == "ok" else 503)
                    return
            except httpx.HTTPError:
                pass
            time.sleep(1)
    pytest.fail(f"Readiness did not reach database={database}, worker={worker}")


def test_healthy_services_and_example_job():
    await_ready("ok", "ok")

    async def defer():
        app = create_task_app(Settings())
        async with app.open_async():
            return await app.tasks["example_job"].defer_async()

    job_id = asyncio.run(defer())
    engine = make_engine(Settings())
    try:
        deadline = time.monotonic() + 30
        while time.monotonic() < deadline:
            with Session(engine) as session:
                status = session.scalar(select(QueueJob.status).where(QueueJob.id == job_id))
            if status == "succeeded":
                break
            time.sleep(0.5)
        else:
            pytest.fail("Example job did not complete")
        # PostGIS must already be installed by the image, not application SQL.
        assert "spatial_ref_sys" in inspect(engine).get_table_names()
        with Session(engine) as session:
            assert session.scalar(select(func.current_setting("statement_timeout"))) == "5s"
            assert session.scalar(select(func.current_setting("search_path"))) == "public"
        # These vendor tables remain present, but must not appear in our migration diff.
        assert inspect(engine).get_table_names(schema="tiger")
    finally:
        engine.dispose()


def test_models_match_migrations(tmp_path):
    config = Config("alembic.ini")
    # Keep generated files in the disposable test container, not the source tree.
    versions = tmp_path / "versions"
    versions.mkdir()
    config.set_main_option(
        "version_locations", os.pathsep.join([str(versions), "migrations/versions"])
    )
    revision = command.revision(
        config, message="unchanged", autogenerate=True, version_path=str(versions)
    )
    module = ast.parse(Path(revision.path).read_text(encoding="utf-8"))
    functions = {node.name: node.body for node in module.body if isinstance(node, ast.FunctionDef)}
    for name in ("upgrade", "downgrade"):
        assert len(functions[name]) == 1 and isinstance(functions[name][0], ast.Pass), ast.unparse(
            module
        )


SHA256 = "0" * 64


def _detector(version, sha256=SHA256):
    return DetectorModel(
        version=version, artifact_uri="gs://private/models", artifact_sha256=sha256, metrics={}
    )


def test_vision_registry_rejects_duplicate_versions_and_unweighed_crops():
    engine = make_engine(Settings())
    rejected = [
        [_detector("dup"), _detector("dup")],
        [_detector("bad-sha", sha256="not-a-sha")],
        [WeightFormula(crop="cabbage", version="dup", formula={}) for _ in range(2)],
        [WeightFormula(crop="spinach", version="v1", formula={})],
    ]
    try:
        for rows in rejected:
            with Session(engine) as session:
                session.add_all(rows)
                with pytest.raises(IntegrityError):
                    session.flush()
        with Session(engine) as session:
            session.add(_detector("registered"))
            session.commit()
        database = Database(Settings())
        try:
            assert exists("registered", database)
            assert not exists("never-registered", database)
        finally:
            database.close()
        with Session(engine) as session:
            session.delete(session.scalars(select(DetectorModel)).one())
            session.commit()
    finally:
        engine.dispose()


def test_worker_down():
    await_ready("ok", "down")


def test_recovered():
    await_ready("ok", "ok")


def test_database_down():
    await_ready("down", "down")
    with httpx.Client(base_url=os.environ["API_URL"], timeout=15) as client:
        response = client.get("/health/live")
        assert response.status_code == 200
        assert response.json() == {"status": "ok", "sha": os.environ["COMMIT_SHA"]}
