"""The additive migration must match ORM constraints without raw SQL (#11)."""

import io

from alembic import command
from alembic.config import Config
from test_farm_schema import _index_statements, _orm_sql, _table_elements

NEW_TABLES = ("section_kinds", "crop_types", "crop_calendars", "planting_crops")


def test_migration_head_includes_login_leases_and_crop_catalogue():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0024:head", sql=True)
    sql = output.getvalue()
    assert "ADD COLUMN login_leases" in sql
    for table in NEW_TABLES:
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)


def test_crop_catalogue_migration_is_additive_and_matches_models():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0025:0026", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql
    assert "DROP TABLE" not in sql
    for table in NEW_TABLES:
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)
        assert _index_statements(sql, table) == _index_statements(_orm_sql(table), table)


def test_crop_catalogue_migration_seeds_the_expected_crops():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0025:0026", sql=True)
    sql = output.getvalue()
    for code in ("cabbage", "spinach", "tomato", "potato", "onion", "carrot"):
        assert f"'{code}'" in sql
    assert "INSERT INTO crop_calendars" not in sql
