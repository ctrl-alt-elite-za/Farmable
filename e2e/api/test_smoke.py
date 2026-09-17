"""Public API behaviour against the actual production API + worker, not an ASGI fake."""

import os
import time
from uuid import UUID

import httpx
import pytest

pytestmark = pytest.mark.integration


def test_ready_and_live():
    deadline = time.monotonic() + 60
    with httpx.Client(base_url=os.environ["API_URL"], timeout=10) as client:
        while time.monotonic() < deadline:
            try:
                ready = client.get("/health/ready")
                if ready.status_code == 200:
                    break
            except httpx.HTTPError:
                pass
            time.sleep(1)
        else:
            pytest.fail("Production API + worker did not become ready")
        assert ready.json() == {"database": "ok", "worker": "ok", "sha": os.environ["COMMIT_SHA"]}
        assert UUID(ready.headers["x-request-id"])
        live = client.get("/health/live")
        assert live.status_code == 200
        assert live.json() == {"status": "ok", "sha": os.environ["COMMIT_SHA"]}


def test_errors_and_request_correlation():
    rid = "ee081a44-717b-480c-a38a-ff4fc94e2587"
    with httpx.Client(base_url=os.environ["API_URL"], timeout=10) as client:
        response = client.get("/missing", headers={"X-Request-ID": rid})
    assert response.status_code == 404
    assert response.json() == {"error": {"code": "http_error", "message": "Not Found"}}
    assert response.headers["x-request-id"] == rid


def test_openapi_exposes_health_contract():
    with httpx.Client(base_url=os.environ["API_URL"], timeout=10) as client:
        response = client.get("/openapi.json")
    assert response.status_code == 200
    assert "/health/ready" in response.json()["paths"]
