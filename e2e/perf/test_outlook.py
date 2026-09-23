"""Authenticated ASGI + PostgreSQL latency; excludes network and live providers."""

import math
from time import perf_counter

import pytest
from alembic import command
from farmable_backend.config import Settings
from farmable_backend.forecast_contract import CROPS
from farmable_backend.forecasts import import_bundle
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.main import create_app
from farmable_backend.models import Farm, Section
from farmable_backend.records_api import RecordRuntime
from farmable_backend.records_service import RecordsService
from fastapi.testclient import TestClient
from test_forecasts import bundle, raw

pytestmark = pytest.mark.integration


def test_outlook_seeded_postgres_p95(pg, record_property):
    command.upgrade(pg.config, "0007")
    import_bundle(pg.sessions, "sample-v1", raw(bundle()), "sample")
    # A nontrivial, explicitly reported population, not a one-row microbenchmark.
    with pg.sessions.begin() as session:
        farms = [Farm(owner_id=pg.ids.other, name=f"Perf farm {i}") for i in range(100)]
        session.add_all(farms)
        session.flush()
        session.add_all(
            [
                Section(owner_id=pg.ids.other, farm_id=farm.id, name=f"Section {j}")
                for farm in farms
                for j in range(10)
            ]
        )
    app = create_app(
        Settings(forecast_data_mode="sample"),
        readiness=lambda: {"database": "ok", "worker": "ok"},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    app.state.records = RecordRuntime(RecordsService(pg.sessions), lambda: None)
    samples = []
    with TestClient(app, headers={"Authorization": pg.ids.authorization}) as client:
        # 8 warmups + 96 measured requests fit the unchanged 120/minute IP limiter.
        queries = [(crop, 1) for crop in CROPS] + [
            (crop, month) for crop in CROPS for month in range(1, 13)
        ]
        for index, (crop, month) in enumerate(queries):
            started = perf_counter()
            response = client.get(
                "/outlook",
                params={
                    "section_id": str(pg.ids.section),
                    "crop": crop,
                    "plant_month": month,
                },
            )
            elapsed = (perf_counter() - started) * 1000
            assert response.status_code == 200
            payload = response.json()
            assert payload["crop"] == crop and payload["plant_month"] == month
            assert payload["run_id"] == "sample-v1" and payload["warning"]
            if index >= len(CROPS):
                samples.append(elapsed)
        assert not app.state.services.transport.calls
    p95 = sorted(samples)[math.ceil(len(samples) * 0.95) - 1]
    record_property("outlook_p95_ms", round(p95, 3))
    record_property("measured_requests", len(samples))
    print(
        f"outlook: warmups=8 requests={len(samples)} added_farms=100 "
        f"added_sections=1000 concurrency=1 p95_ms={p95:.3f}"
    )
    assert p95 < 200, f"Seeded PostgreSQL outlook p95 {p95:.3f}ms exceeds 200ms"
