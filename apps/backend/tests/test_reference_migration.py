"""Reference migration is additive and keeps the frozen schema in sync with ORM."""

import io

from alembic import command
from alembic.config import Config
from test_farm_schema import _orm_sql, _table_elements


def test_reference_migration_matches_orm():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0016:0017", sql=True)
    sql = output.getvalue()
    assert "ALTER TABLE" not in sql
    assert "DROP TABLE" not in sql
    for table in (
        "reference_imports",
        "reference_market_prices",
        "reference_crop_calendars",
        "reference_crop_costs",
    ):
        assert _table_elements(sql, table) == _table_elements(_orm_sql(table), table)
