"""Durable quota races and migration in the disposable PostgreSQL harness."""

from concurrent.futures import ThreadPoolExecutor
from threading import Barrier

import pytest
from alembic import command
from farmable_backend.models import AuthIdentity, VoiceSessionRate
from farmable_backend.record_access import ApiError
from farmable_backend.voice_api import admit
from sqlalchemy import inspect
from test_photo_sync_postgres import pg  # noqa: F401 -- isolated schema fixture

pytestmark = pytest.mark.integration


def test_concurrent_first_issuance_is_limited_across_connections(request):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0006")
    barrier = Barrier(6)

    def issue():
        barrier.wait(timeout=10)
        try:
            admit(database.sessions, database.ids.authorization, True)
            return "admitted"
        except ApiError as error:
            return error.code

    with ThreadPoolExecutor(max_workers=6) as executor:
        results = list(executor.map(lambda _: issue(), range(6)))
    assert results.count("admitted") == 3
    assert results.count("voice_rate_limited") == 3
    with database.sessions() as session:
        assert len(session.get(VoiceSessionRate, database.ids.owner).hits) == 3


def test_upgrade_downgrade_preserves_authentication(request):
    database = request.getfixturevalue("pg")
    command.upgrade(database.config, "0006")
    admit(database.sessions, database.ids.authorization, True)
    assert "voice_session_rates" in inspect(database.engine).get_table_names()
    command.downgrade(database.config, "0005")
    assert "voice_session_rates" not in inspect(database.engine).get_table_names()
    with database.sessions() as session:
        assert session.get(AuthIdentity, database.ids.owner).phone_verified
    command.upgrade(database.config, "0006")
    admit(database.sessions, database.ids.authorization, True)
