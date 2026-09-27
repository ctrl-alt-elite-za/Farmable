"""Farm-profile and funding/procurement matching routes (owner-scoped, source-backed)."""

from datetime import UTC, date, datetime, timedelta
from types import SimpleNamespace

import pytest
from farmable_backend.account import AccountService
from farmable_backend.account_api import AccountRuntime
from farmable_backend.advisory import AdvisoryService
from farmable_backend.auth import AuthService, Channel, DeterministicFakeOtpProvider, SessionTokens
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.main import create_app
from farmable_backend.models import AdvisoryOpportunity, Base, FarmProfile
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, select
from sqlalchemy.orm import sessionmaker
from sqlalchemy.pool import StaticPool

PASSWORD = "correct horse battery staple"  # noqa: S105 - synthetic test credential


def _register(auth, first_name, surname, phone, email):
    user = auth.signup(first_name, surname, phone, email, PASSWORD)
    auth.verify(user.id, Channel.PHONE, "111111")
    tokens = auth.verify(user.id, Channel.EMAIL, "222222")
    assert isinstance(tokens, SessionTokens)
    return tokens


def _headers(tokens):
    return {"Authorization": f"Bearer {tokens.access_token}"}


def _opportunity(name, *, kind="funding", closes_on=None, **values):
    return AdvisoryOpportunity(
        kind=kind,
        name=name,
        provider="Test provider",
        summary=f"{name} summary",
        closes_on=closes_on,
        deadline_note="See source",
        source_url="https://example.org/source",
        verified_on=date(2026, 9, 1),
        **values,
    )


@pytest.fixture
def advisory(settings):
    engine = create_engine(
        "sqlite+pysqlite:///:memory:",
        poolclass=StaticPool,
        connect_args={"check_same_thread": False},
    )

    @event.listens_for(engine, "connect")
    def enable_foreign_keys(dbapi_connection, _connection_record):
        cursor = dbapi_connection.cursor()  # raw-sql: allow -- SQLite test configuration.
        cursor.execute("PRAGMA foreign_keys=ON")  # raw-sql: allow -- SQLite test configuration.
        cursor.close()

    Base.metadata.create_all(engine)
    sessions = sessionmaker(engine, expire_on_commit=False)
    auth = AuthService(sessions, DeterministicFakeOtpProvider())
    alice = _register(auth, "Sipho", "Dlamini", "+27123456789", "sipho@example.com")
    bob = _register(auth, "Nandi", "Mokoena", "+27820000000", "nandi@example.com")
    today = datetime.now(UTC).date()
    with sessions.begin() as session:
        session.add_all(
            [
                _opportunity("Open grant", closes_on=today + timedelta(days=30), province="all"),
                _opportunity("Rolling grant", province="KwaZulu-Natal", crops=["cabbage"]),
                _opportunity("Closed grant", closes_on=today - timedelta(days=1)),
                _opportunity("Retired grant", active=False),
                _opportunity("Other province grant", province="Limpopo"),
                _opportunity("School feeding", kind="procurement"),
            ]
        )
    app = create_app(
        settings,
        readiness=lambda: {"database": "ok", "worker": "ok"},
        service_settings=ServiceSettings(environment="ci", integrations_mode="fake"),
    )
    app.state.auth = auth
    app.state.account = AccountRuntime(AccountService(sessions))
    app.state.advisory = AccountRuntime(AdvisoryService(sessions))
    with TestClient(app) as client:
        yield SimpleNamespace(client=client, sessions=sessions, alice=alice, bob=bob)
    engine.dispose()


def test_profile_requires_a_session(advisory):
    response = advisory.client.get("/advisory/farm-profile")
    assert response.status_code == 401


def test_empty_profile_then_update_persists_for_the_owner_only(advisory):
    alice, bob = _headers(advisory.alice), _headers(advisory.bob)
    empty = advisory.client.get("/advisory/farm-profile", headers=alice)
    assert empty.status_code == 200
    assert empty.headers["cache-control"] == "no-store"
    assert empty.json()["province"] is None and empty.json()["crops"] == []

    updated = advisory.client.patch(
        "/advisory/farm-profile",
        headers=alice,
        json={"province": "KwaZulu-Natal", "crops": ["Cabbage"], "farm_size_ha": "2.5"},
    )
    assert updated.status_code == 200
    assert updated.json()["province"] == "KwaZulu-Natal"
    assert updated.json()["owner_id"] == str(advisory.alice.user.id)

    partial = advisory.client.patch(
        "/advisory/farm-profile", headers=alice, json={"farmer_type": "smallholder"}
    )
    assert partial.json()["province"] == "KwaZulu-Natal"
    assert partial.json()["farmer_type"] == "smallholder"
    assert advisory.client.get("/advisory/farm-profile", headers=bob).json()["province"] is None


@pytest.mark.parametrize("body", [{"unknown": 1}, {"farm_size_ha": "0"}, {"province": "x" * 101}])
def test_profile_update_rejects_invalid_fields(advisory, body):
    response = advisory.client.patch(
        "/advisory/farm-profile", headers=_headers(advisory.alice), json=body
    )
    assert response.status_code == 422


def test_matches_exclude_closed_inactive_and_other_province_rows(advisory):
    alice = _headers(advisory.alice)
    advisory.client.patch(
        "/advisory/farm-profile",
        headers=alice,
        json={"province": "KwaZulu-Natal", "crops": ["cabbage"]},
    )
    response = advisory.client.get("/advisory/opportunities/funding", headers=alice)
    assert response.status_code == 200
    matches = response.json()
    # The crop match ranks the rolling grant first; its unpublished deadline stays open.
    assert [item["name"] for item in matches] == ["Rolling grant", "Open grant"]
    assert "crop interest matches" in matches[0]["match_reasons"]
    assert "deadline is open or not published" in matches[0]["match_reasons"]
    assert matches[0]["closes_on"] is None


def test_matches_without_a_profile_only_show_nationwide_rows(advisory):
    response = advisory.client.get(
        "/advisory/opportunities/funding", headers=_headers(advisory.bob)
    )
    assert [item["name"] for item in response.json()] == ["Open grant"]


def test_matches_are_split_by_kind_and_limited(advisory):
    alice = _headers(advisory.alice)
    procurement = advisory.client.get("/advisory/opportunities/procurement", headers=alice)
    assert [item["name"] for item in procurement.json()] == ["School feeding"]
    advisory.client.patch("/advisory/farm-profile", headers=alice, json={"province": "all"})
    limited = advisory.client.get("/advisory/opportunities/funding?limit=1", headers=alice)
    assert len(limited.json()) == 1


@pytest.mark.parametrize(
    "path",
    [
        "/advisory/opportunities/loans",
        "/advisory/opportunities/funding?limit=0",
        "/advisory/opportunities/funding?limit=21",
    ],
)
def test_matches_reject_unknown_kinds_and_limits(advisory, path):
    response = advisory.client.get(path, headers=_headers(advisory.alice))
    assert response.status_code == 422


def test_export_includes_only_the_callers_profile_and_delete_removes_it(advisory):
    alice, bob = _headers(advisory.alice), _headers(advisory.bob)
    advisory.client.patch("/advisory/farm-profile", headers=alice, json={"province": "Gauteng"})
    advisory.client.patch("/advisory/farm-profile", headers=bob, json={"province": "Limpopo"})

    document = advisory.client.get("/account/export?format=json", headers=alice).json()
    assert [row["province"] for row in document["farm_profiles"]] == ["Gauteng"]
    assert "Limpopo" not in str(document)

    removed = advisory.client.request(
        "DELETE", "/account", headers=alice, json={"password": PASSWORD}
    )
    assert removed.status_code == 204
    with advisory.sessions() as session:
        owners = session.scalars(select(FarmProfile.owner_id)).all()
    assert owners == [advisory.bob.user.id]
