"""The additive migration must match ORM constraints without raw SQL."""

import io

from alembic import command
from alembic.config import Config
from test_farm_schema import _index_statements, _orm_sql, _table_elements


def test_photo_migration_is_additive_and_matches_models():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0004:0005", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql
    assert "DROP TABLE" not in sql
    for table in ("photo_uploads", "photo_attempts", "photo_rates"):
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)
        assert _index_statements(sql, table) == _index_statements(_orm_sql(table), table)
