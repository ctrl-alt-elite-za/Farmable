import io

from alembic import command
from alembic.config import Config
from test_farm_schema import _index_statements, _orm_sql, _table_elements


def test_assistant_migration_matches_models_and_seeds_budget_lock():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0009:0010", sql=True)
    sql = output.getvalue()
    assert "DROP TABLE" not in sql and "ALTER TABLE" not in sql
    assert "INSERT INTO assistant_budget (id) VALUES (1)" in sql
    assert "SERIAL" not in sql  # The singleton has an explicit ID, not a sequence.
    for name in ("assistant_conversations", "assistant_turns", "assistant_budget"):
        assert _table_elements(sql, name) == _table_elements(_orm_sql(name), name)
        assert _index_statements(sql, name) == _index_statements(_orm_sql(name), name)
