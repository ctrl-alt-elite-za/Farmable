"""The pending-contact-change/farm-location migration is additive and matches the ORM."""

import io

from alembic import command
from alembic.config import Config
from test_farm_schema import _index_statements, _orm_sql, _table_elements


def test_profile_contact_and_farm_location_migration_is_additive_and_matches_the_orm():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0010:0011", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql
    assert "DROP TABLE" not in sql
    assert "UPDATE auth_identities" not in sql
    assert "UPDATE farms" not in sql
    for table in ("pending_contact_changes", "farm_locations"):
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)
        assert _index_statements(sql, table) == _index_statements(_orm_sql(table), table)
