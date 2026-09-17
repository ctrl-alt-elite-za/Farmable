"""Real dependency failure injection while optional service fault flags await #7."""

import os
import time

import httpx
import pytest

pytestmark = pytest.mark.integration


def assert_state(database, worker):
    with httpx.Client(base_url=os.environ["API_URL"], timeout=15) as client:
        deadline = time.monotonic() + 60
        while time.monotonic() < deadline:
            response = client.get("/health/ready")
            if response.json() == {
                "database": database,
                "worker": worker,
                "sha": os.environ["COMMIT_SHA"],
            }:
                break
            time.sleep(1)
        else:
            pytest.fail("Dependency state did not propagate to readiness")
        assert response.status_code == (200 if database == worker == "ok" else 503)
        assert client.get("/health/live").status_code == 200


def test_worker_down():
    assert_state("ok", "down")


def test_recovered():
    assert_state("ok", "ok")


def test_database_down():
    assert_state("down", "down")
