"""Offline migration checks protect existing ownership tables and ORM parity."""

import io

from alembic import command
from alembic.config import Config
from farmable_backend.models import AuthSession
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateColumn
from test_farm_schema import _index_statements, _orm_sql, _table_elements


def rotation_columns() -> list[str]:
    return [
        str(CreateColumn(column).compile(dialect=postgresql.dialect())).strip()
        for column in (AuthSession.__table__.c.replaced_by_id, AuthSession.__table__.c.used_at)
    ]


def test_auth_migration_only_creates_new_tables_matching_the_orm():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0003:0004", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE users" not in sql
    assert "UPDATE users" not in sql
    assert "CREATE INDEX" not in sql.split("CREATE TABLE auth_identities", 1)[0]
    for table in ("auth_identities", "verification_challenges", "auth_sessions"):
        elements = _table_elements(_orm_sql(table), table)
        if table == "auth_sessions":
            # 0028 adds exactly these elements; 0004 remains immutable.
            for column in rotation_columns():
                elements.remove(column)
        assert _table_elements(sql, table) == elements
        assert _index_statements(sql, table) == _index_statements(_orm_sql(table), table)


def test_refresh_rotation_migration_is_additive_and_matches_model():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0027:0028", sql=True)
    sql = output.getvalue()
    for column in rotation_columns():
        assert f"ALTER TABLE auth_sessions ADD COLUMN {column};" in sql
    assert "DROP" not in sql and "UPDATE auth_sessions" not in sql
