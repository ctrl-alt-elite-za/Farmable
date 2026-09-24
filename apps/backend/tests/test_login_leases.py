"""Admission recovery and fencing, without live credentials or provider calls."""

import io

import pytest
from alembic import command
from alembic.config import Config
from farmable_backend import rate_limits as limits
from farmable_backend.models import RateLimitCounter
from test_auth import _database_auth


def test_abandoned_logins_expire_without_worker_cleanup(monkeypatch):
    sessions, _ = _database_auth()
    monkeypatch.setattr(limits, "_now_ts", lambda: 1000.0)
    args = {"account": "lease@example.com", "ip": "192.0.2.1"}
    for _ in range(limits.LOGIN_IN_FLIGHT_LIMIT):
        limits.admit_login(sessions, **args)
    with pytest.raises(limits.RateLimited) as caught:
        limits.admit_login(sessions, **args)
    assert caught.value.retry_after == limits.LOGIN_LEASE_SECONDS
    monkeypatch.setattr(limits, "_now_ts", lambda: 1000.0 + limits.LOGIN_LEASE_SECONDS)
    ticket = limits.admit_login(sessions, **args)
    with sessions.begin() as session:
        assert limits.finish_login(session, **args, reservation=ticket, success=True)


@pytest.mark.parametrize("success", [False, True])
def test_expired_completion_cannot_release_new_lease_or_record_a_failure(monkeypatch, success):
    sessions, _ = _database_auth()
    args = {"account": "lease@example.com", "ip": "192.0.2.1"}
    monkeypatch.setattr(limits, "_now_ts", lambda: 1000.0)
    old = limits.admit_login(sessions, **args)
    monkeypatch.setattr(limits, "_now_ts", lambda: 1000.0 + limits.LOGIN_LEASE_SECONDS)
    new = limits.admit_login(sessions, **args)
    with sessions.begin() as session:
        assert not limits.finish_login(session, **args, reservation=old, success=success)
    with sessions() as session:
        for scope, subject in (
            ("login_fail_account", args["account"]),
            ("login_fail_ip", args["ip"]),
        ):
            row = session.get(RateLimitCounter, (scope, limits.hash_subject(subject)))
            assert set(row.login_leases) == {new} and row.in_flight == 1 and not row.hits
    with sessions.begin() as session:
        assert limits.finish_login(session, **args, reservation=new, success=True)
    with sessions.begin() as session:
        assert not limits.finish_login(session, **args, reservation=new, success=True)


def test_failure_lockout_survives_lease_expiry(monkeypatch):
    sessions, _ = _database_auth()
    args = {"account": "lease@example.com", "ip": "192.0.2.1"}
    monkeypatch.setattr(limits, "_now_ts", lambda: 1000.0)
    for _ in range(5):
        ticket = limits.admit_login(sessions, **args)
        with sessions.begin() as session:
            assert limits.finish_login(session, **args, reservation=ticket, success=False)
    monkeypatch.setattr(limits, "_now_ts", lambda: 1000.0 + limits.LOGIN_LEASE_SECONDS)
    with pytest.raises(limits.RateLimited):
        limits.admit_login(sessions, **args)


def test_login_lease_migration_matches_column():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0023:0024", sql=True)
    assert "ADD COLUMN login_leases JSONB DEFAULT '{}' NOT NULL" in output.getvalue()
    column = RateLimitCounter.__table__.c.login_leases
    assert not column.nullable and column.server_default.arg == "{}"
