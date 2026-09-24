"""The mobile challenge page is public, bounded and never a production bypass."""

import json
from html.parser import HTMLParser
from uuid import uuid4

import pytest
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.main import create_app
from fastapi.testclient import TestClient
from pydantic import SecretStr


class PageConfig(HTMLParser):
    def __init__(self, html):
        super().__init__()
        self.config = None
        self.read_config = False
        self.feed(html)

    def handle_starttag(self, tag, attrs):
        self.read_config = tag == "script" and dict(attrs).get("id") == "challenge-config"

    def handle_data(self, data):
        if self.read_config:
            self.config = json.loads(data)

    def handle_endtag(self, tag):
        if tag == "script":
            self.read_config = False


@pytest.mark.parametrize("action", ["sign_up", "login"])
def test_ci_challenge_page_carries_only_the_requested_action_and_state(settings, action):
    app = create_app(
        settings,
        readiness=lambda: {},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    state = str(uuid4())
    with TestClient(app) as client:
        response = client.get("/auth/turnstile", params={"action": action, "state": state})
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/html")
    assert response.headers["cache-control"] == "no-store"
    assert response.headers["referrer-policy"] == "no-referrer"
    assert "frame-ancestors 'none'" in response.headers["content-security-policy"]
    assert PageConfig(response.text).config == {
        "action": action,
        "state": state,
        "sitekey": None,
        "simulation": True,
    }


@pytest.mark.parametrize("mode", ["disabled", "live"])
def test_unconfigured_production_challenge_fails_closed(settings, mode):
    app = create_app(
        settings,
        readiness=lambda: {},
        service_settings=ServiceSettings(environment="production", integrations_mode=mode),
    )
    with TestClient(app) as client:
        response = client.get("/auth/turnstile", params={"action": "login", "state": uuid4()})
    assert response.status_code == 503


def test_live_page_exposes_public_key_but_never_the_server_secret(settings):
    integration = ServiceSettings(
        environment="production",
        integrations_mode="live",
        turnstile_secret=SecretStr("server-only-fixture-secret"),
        turnstile_hostname="api.farmable.test",
        turnstile_site_key="0xPublicFixtureKey",
    )
    app = create_app(settings, readiness=lambda: {}, service_settings=integration)
    state = str(uuid4())
    with TestClient(app, base_url="https://api.farmable.test") as client:
        first = client.get("/auth/turnstile", params={"action": "sign_up", "state": state})
        second = client.get("/auth/turnstile", params={"action": "sign_up", "state": state})
    assert first.status_code == second.status_code == 200
    assert PageConfig(first.text).config == {
        "action": "sign_up",
        "state": state,
        "sitekey": "0xPublicFixtureKey",
        "simulation": False,
    }
    assert "server-only-fixture-secret" not in first.text
    assert first.headers["content-security-policy"] != second.headers["content-security-policy"]


def test_live_challenge_refuses_unapproved_host_and_ci_simulation_is_not_available_in_staging(
    settings,
):
    for integration in (
        ServiceSettings(environment="staging", integrations_mode="fake"),
        ServiceSettings(
            environment="production",
            integrations_mode="live",
            turnstile_site_key="public-key",
            turnstile_secret=SecretStr("fixture-secret"),
            turnstile_hostname="approved.farmable.test",
        ),
    ):
        app = create_app(settings, readiness=lambda: {}, service_settings=integration)
        with TestClient(app, base_url="https://other.farmable.test") as client:
            response = client.get("/auth/turnstile", params={"action": "login", "state": uuid4()})
            assert response.status_code == 503
            assert response.headers["cache-control"] == "no-store"


def test_challenge_script_is_served_with_correct_type_and_not_in_api_contract(settings):
    app = create_app(settings, readiness=lambda: {})
    with TestClient(app) as client:
        response = client.get("/auth/turnstile.js")
    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/javascript")
    assert response.headers["x-content-type-options"] == "nosniff"
    assert "/auth/turnstile" not in app.openapi()["paths"]
    assert "/auth/turnstile.js" not in app.openapi()["paths"]


@pytest.mark.parametrize(
    "query",
    [
        {"action": "other", "state": str(uuid4())},
        {"action": "login", "state": "</script><script>alert(1)</script>"},
        {"action": "login"},
    ],
)
def test_challenge_rejects_unbound_or_injected_requests(settings, query):
    app = create_app(
        settings,
        readiness=lambda: {},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    with TestClient(app) as client:
        assert client.get("/auth/turnstile", params=query).status_code == 422
