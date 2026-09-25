import json
import logging
from uuid import UUID, uuid4

import pytest
from farmable_backend.account_api import client_ip as account_client_ip
from farmable_backend.logging import JsonFormatter, request_id
from farmable_backend.main import create_app
from farmable_backend.middleware import RateLimiter, client_address
from farmable_backend.schemas import StrictModel
from fastapi import HTTPException, Request
from fastapi.testclient import TestClient


def test_health(settings):
    with TestClient(
        create_app(settings, readiness=lambda: {"database": "ok", "worker": "ok"})
    ) as client:
        assert client.get("/health/live").json() == {"status": "ok", "sha": "test-sha"}
        ready = client.get("/health/ready")
        assert ready.status_code == 200
        assert ready.json() == {"database": "ok", "worker": "ok", "sha": "test-sha"}


@pytest.mark.parametrize("failed", ["database", "worker"])
def test_dependency_down(settings, failed):
    status = {"database": "ok", "worker": "ok", failed: "down"}
    with TestClient(create_app(settings, readiness=lambda: status)) as client:
        response = client.get("/health/ready")
        assert response.status_code == 503
        assert response.json() == {**status, "sha": "test-sha"}
        assert client.get("/health/live").status_code == 200


def test_readiness_never_exposes_errors(settings):
    def broken():
        raise RuntimeError("postgres://sensitive-host secret=password")

    with TestClient(create_app(settings, readiness=broken)) as client:
        response = client.get("/health/ready")
        assert response.status_code == 503
        assert response.json() == {"database": "down", "worker": "down", "sha": "test-sha"}


def test_global_rate_limit(settings):
    now = [100.0]
    app = create_app(settings, readiness=lambda: {}, limiter=RateLimiter(clock=lambda: now[0]))
    with TestClient(app) as client:
        for _ in range(120):
            assert client.get("/health/live").status_code == 200
        response = client.get("/health/live", headers={"X-Forwarded-For": "different-ip"})
        assert response.status_code == 429
        assert response.json() == {
            "error": {"code": "rate_limited", "message": "Too many requests"}
        }
        assert response.headers["retry-after"] == "60"
        assert UUID(response.headers["x-request-id"])
        now[0] += 60
        assert client.get("/health/live").status_code == 200


def test_rate_limit_is_per_ip_and_bounded():
    now = [1.0]
    limiter = RateLimiter(clock=lambda: now[0], max_ips=2)
    for _ in range(120):
        assert limiter.retry_after("a") is None
    assert limiter.retry_after("a") == 60
    assert limiter.retry_after("b") is None
    assert limiter.retry_after("c") == 60
    now[0] += 60
    assert limiter.retry_after("c") is None
    assert len(limiter.hits) == 1


def _scope(peer: str, *forwarded: str) -> dict:
    headers = [(b"x-forwarded-for", value.encode()) for value in forwarded]
    return {"type": "http", "client": (peer, 1234), "headers": headers}


def test_client_address_ignores_forwarded_for_without_a_trusted_proxy():
    scope = _scope("198.51.100.7", "203.0.113.9")
    assert client_address(scope) == "198.51.100.7"
    assert client_address(scope, 0) == "198.51.100.7"


@pytest.mark.parametrize(
    ("forwarded", "hops", "expected"),
    [
        # The trusted proxy appends the caller; client-supplied entries sit left of it.
        (("203.0.113.9",), 1, "203.0.113.9"),
        (("6.6.6.6, 203.0.113.9",), 1, "203.0.113.9"),
        (("6.6.6.6", "203.0.113.9"), 1, "203.0.113.9"),
        (("6.6.6.6,203.0.113.9, 192.0.2.1",), 2, "203.0.113.9"),
        (("2001:db8::1",), 1, "2001:db8::1"),
        # Missing or malformed trusted entries fall back to the shared peer bucket.
        ((), 1, "169.254.1.1"),
        (("203.0.113.9",), 2, "169.254.1.1"),
        (("6.6.6.6, not-an-ip",), 1, "169.254.1.1"),
        (("6.6.6.6, ",), 1, "169.254.1.1"),
    ],
)
def test_client_address_trusts_only_proxy_appended_entries(forwarded, hops, expected):
    assert client_address(_scope("169.254.1.1", *forwarded), hops) == expected


def test_trusted_proxy_gives_each_caller_its_own_bucket_and_ignores_spoofing(settings):
    now = [100.0]
    app = create_app(
        settings.model_copy(update={"trusted_proxy_hops": 1}),
        readiness=lambda: {},
        limiter=RateLimiter(clock=lambda: now[0]),
    )
    with TestClient(app) as client:
        for index in range(120):
            # A fresh spoofed left-hand entry each time must not reset the bucket.
            spoofed = f"10.0.0.{index % 250}, 203.0.113.9"
            response = client.get("/health/live", headers={"X-Forwarded-For": spoofed})
            assert response.status_code == 200
        blocked = client.get("/health/live", headers={"X-Forwarded-For": "1.2.3.4, 203.0.113.9"})
        assert blocked.status_code == 429
        # Another caller behind the same front-end proxy is unaffected.
        other = client.get("/health/live", headers={"X-Forwarded-For": "203.0.113.10"})
        assert other.status_code == 200


def test_account_routes_use_the_middleware_resolved_client():
    request = Request(
        {
            "type": "http",
            "client": ("169.254.1.1", 1234),
            "headers": [(b"x-forwarded-for", b"6.6.6.6")],
            "state": {"client_ip": "203.0.113.9"},
        }
    )
    assert account_client_ip(request) == "203.0.113.9"


class TestPayload(StrictModel):
    __test__ = False
    name: str


def test_unknown_fields_are_rejected(settings):
    app = create_app(settings, readiness=lambda: {})

    @app.post("/test")
    async def test_endpoint(payload: TestPayload):
        return payload

    with TestClient(app) as client:
        assert client.post("/test", json={"name": "known"}).status_code == 200
        response = client.post("/test", json={"name": "known", "unknown": "secret"})
        assert response.status_code == 422
        assert response.json() == {
            "error": {"code": "validation_error", "message": "Invalid request"}
        }
        assert "secret" not in response.text


def test_errors_share_envelope_and_request_id(settings):
    app = create_app(settings, readiness=lambda: {})

    @app.get("/explode")
    async def explode():
        raise RuntimeError("secret exception")

    @app.get("/denied")
    async def denied():
        raise HTTPException(403, detail="private detail")

    with TestClient(app) as client:
        for path, status, code in [
            ("/missing", 404, "http_error"),
            ("/denied", 403, "http_error"),
            ("/explode", 500, "internal_error"),
        ]:
            response = client.get(path)
            assert response.status_code == status
            assert response.json()["error"]["code"] == code
            assert UUID(response.headers["x-request-id"])
            assert "secret" not in response.text
            assert "private" not in response.text


def test_request_id_propagates_to_logs_and_resets(settings):
    app = create_app(settings, readiness=lambda: {})
    observed = []

    @app.get("/context")
    async def context(request: Request):
        record = logging.LogRecord("test", logging.INFO, __file__, 1, "hello", (), None)
        observed.append(json.loads(JsonFormatter().format(record)))
        return {"request_id": request.state.request_id}

    rid = str(uuid4())
    with TestClient(app) as client:
        response = client.get("/context", headers={"X-Request-ID": rid})
        assert response.headers["x-request-id"] == rid
        assert response.json()["request_id"] == rid
        assert observed[-1]["request_id"] == rid
        response = client.get("/context", headers={"X-Request-ID": "user-secret"})
        assert response.headers["x-request-id"] != "user-secret"
    assert request_id.get() == "system"


def test_openapi_has_standard_errors_and_readiness():
    schema = create_app().openapi()
    responses = schema["paths"]["/health/ready"]["get"]["responses"]
    for status in ["422", "429", "500"]:
        assert responses[status]["content"]["application/json"]["schema"]["$ref"].endswith(
            "/ErrorResponse"
        )
    assert responses["503"]["content"]["application/json"]["schema"]["$ref"].endswith(
        "/ReadyResponse"
    )
    assert "HTTPValidationError" not in schema["components"]["schemas"]
