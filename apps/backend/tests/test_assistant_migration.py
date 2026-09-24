import io

from alembic import command
from alembic.config import Config
from farmable_backend.models import AssistantTurn
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateColumn, CreateIndex
from test_farm_schema import _index_statements, _orm_sql, _table_elements


def test_assistant_migration_matches_models_and_seeds_budget_lock():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0009:0010", sql=True)
    sql = output.getvalue()
    assert "DROP TABLE" not in sql and "ALTER TABLE" not in sql
    assert "INSERT INTO assistant_budget (id) VALUES (1)" in sql
    assert "SERIAL" not in sql  # The singleton has an explicit ID, not a sequence.
    for name in ("assistant_conversations", "assistant_turns", "assistant_budget"):
        elements = _table_elements(_orm_sql(name), name)
        indexes = _index_statements(_orm_sql(name), name)
        if name == "assistant_turns":
            # 0012 adds exactly these elements; 0010 remains immutable.
            elements.remove(retention_column())
            indexes.remove(retention_index())
        assert _table_elements(sql, name) == elements
        assert _index_statements(sql, name) == indexes


def retention_column():
    column = AssistantTurn.__table__.c.content_deleted_at
    return str(CreateColumn(column).compile(dialect=postgresql.dialect())).strip()


def retention_index():
    index = next(
        i for i in AssistantTurn.__table__.indexes if i.name == "ix_assistant_turns_retention"
    )
    return str(CreateIndex(index).compile(dialect=postgresql.dialect()))


def test_retention_migration_is_additive_and_matches_model():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0011:0012", sql=True)
    sql = output.getvalue()
    assert f"ALTER TABLE assistant_turns ADD COLUMN {retention_column()};" in sql
    assert _index_statements(sql, "assistant_turns") == {retention_index()}
    assert "DROP" not in sql and "UPDATE assistant_turns" not in sql


def test_consent_migration_requires_explicit_grants():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0010:0011", sql=True)
    sql = output.getvalue()
    assert "INSERT INTO assistant_consents" not in sql
    name = "assistant_consents"
    assert _table_elements(sql, name) == _table_elements(_orm_sql(name), name)
    assert _index_statements(sql, name) == _index_statements(_orm_sql(name), name)
