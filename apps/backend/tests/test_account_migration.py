"""The account-profile migration is additive and matches the ORM table."""

import io

from alembic import command
from alembic.config import Config
from test_farm_schema import _index_statements, _orm_sql, _table_elements


def test_account_profiles_migration_is_additive_and_matches_the_orm():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0006:0007", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql
    assert "DROP TABLE" not in sql
    assert "UPDATE users" not in sql
    assert "UPDATE auth_identities" not in sql
    assert _table_elements(sql, "account_profiles") == _table_elements(
        _orm_sql("account_profiles"), "account_profiles"
    )
    assert _index_statements(sql, "account_profiles") == _index_statements(
        _orm_sql("account_profiles"), "account_profiles"
    )
