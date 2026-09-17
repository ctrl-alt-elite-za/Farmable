import io
import re
from pathlib import Path

from alembic import command
from alembic.config import Config
from farmable_backend.models import Base
from sqlalchemy.dialects import postgresql
from sqlalchemy.schema import CreateIndex, CreateTable

ROOT = Path(__file__).resolve().parents[3]
VISION_TABLES = ("detector_models", "weight_formulas")


def _table_elements(sql: str, table: str) -> set[str]:
    match = re.search(rf"CREATE TABLE {table} \((.*?)\n\)", sql, re.DOTALL)
    assert match, f"no CREATE TABLE for {table}"
    return {line.strip().rstrip(",") for line in match.group(1).splitlines() if line.strip()}


def _index_statements(sql: str, table: str) -> set[str]:
    return set(re.findall(rf"CREATE (?:UNIQUE )?INDEX \S+ ON {table} \([^)]*\)", sql))


def _migration_sql() -> str:
    output = io.StringIO()
    config = Config(str(ROOT / "alembic.ini"), output_buffer=output)
    config.set_main_option("script_location", str(ROOT / "migrations"))
    command.upgrade(config, "0001:0002", sql=True)
    return output.getvalue()


def _orm_sql(table: str) -> str:
    dialect = postgresql.dialect()
    metadata_table = Base.metadata.tables[table]
    statements = [CreateTable(metadata_table)] + [CreateIndex(i) for i in metadata_table.indexes]
    return ";\n".join(str(statement.compile(dialect=dialect)) for statement in statements)


def test_migration_0002_creates_the_same_vision_tables_as_the_orm():
    migration = _migration_sql()
    for table in VISION_TABLES:
        orm = _orm_sql(table)
        assert _table_elements(migration, table) == _table_elements(orm, table), table
        assert _index_statements(migration, table) == _index_statements(orm, table), table
