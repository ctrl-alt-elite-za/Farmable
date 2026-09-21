"""Offline migration checks protect existing ownership tables and ORM parity."""

import io

from alembic import command
from alembic.config import Config
from test_farm_schema import _index_statements, _orm_sql, _table_elements


def test_auth_migration_only_creates_new_tables_matching_the_orm():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0003:0004", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE users" not in sql
    assert "UPDATE users" not in sql
    assert "CREATE INDEX" not in sql.split("CREATE TABLE auth_identities", 1)[0]
    for table in ("auth_identities", "verification_challenges", "auth_sessions"):
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)
        assert _index_statements(sql, table) == _index_statements(_orm_sql(table), table)
