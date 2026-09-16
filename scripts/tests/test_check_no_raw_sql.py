"""Tests for the AST-based raw-SQL check."""

import ast
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from check_no_raw_sql import check_file, string_valued_names  # noqa: E402


def write(tmp_path: Path, source: str) -> Path:
    path = tmp_path / "sample.py"
    path.write_text(source, encoding="utf-8")
    return path


def test_multiline_execute_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def get_users(cursor):\n"
        "    cursor.execute(\n"
        '        "SELECT * FROM users"\n'
        "    )\n",
    )
    hits = check_file(path)
    assert len(hits) == 1
    assert ":2:" in hits[0]


def test_single_line_execute_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'conn.execute("SELECT 1")\n')
    assert len(check_file(path)) == 1


def test_fstring_execute_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'conn.execute(f"SELECT * FROM {table}")\n')
    assert len(check_file(path)) == 1


def test_concatenated_sql_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'conn.execute("SELECT * FROM " + table)\n')
    assert len(check_file(path)) == 1


def test_multiline_text_call_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "from sqlalchemy import text\n" "stmt = text(\n" '    "SELECT 1"\n' ")\n",
    )
    hits = check_file(path)
    assert len(hits) == 1
    assert "text()" in hits[0]


def test_op_execute_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'op.execute("ALTER TABLE users ADD COLUMN x int")\n')
    assert len(check_file(path)) == 1


def test_multiline_cursor_call_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, "cur = conn.cursor(\n)\n")
    hits = check_file(path)
    assert len(hits) == 1
    assert "cursor()" in hits[0]


def test_orm_code_is_clean(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "from sqlalchemy import select\n"
        "\n"
        "def get_users(session):\n"
        "    return session.scalars(select(User)).all()\n"
        "\n"
        "def run(task):\n"
        "    task.execute(payload)\n",
    )
    assert check_file(path) == []


def test_unparsable_file_is_reported(tmp_path: Path) -> None:
    path = write(tmp_path, "def broken(:\n")
    hits = check_file(path)
    assert len(hits) == 1
    assert "could not parse" in hits[0]


# Review round 2: forms that slipped past the first version of the checker.


def test_op_execute_wrapping_text_is_detected(tmp_path: Path) -> None:
    """The unconditional op.execute() rule must beat the argument-sensitive one."""
    path = write(tmp_path, 'op.execute(sa.text("UPDATE users SET active = 1"))\n')
    hits = check_file(path)
    assert len(hits) == 1
    assert "op.execute()" in hits[0]


def test_qualified_text_call_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'session.execute(sqlalchemy.text("SELECT 1"))\n')
    assert len(check_file(path)) == 1


def test_bare_qualified_text_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'stmt = sa.text("SELECT 1")\n')
    hits = check_file(path)
    assert len(hits) == 1
    assert "sa.text()" in hits[0]


def test_sql_assigned_to_a_variable_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'sql = "DELETE FROM users"\ncursor.execute(sql)\n',
    )
    hits = check_file(path)
    assert len(hits) == 1
    assert ":2:" in hits[0]


def test_exec_driver_sql_is_detected_whatever_the_argument(tmp_path: Path) -> None:
    path = write(tmp_path, "conn.exec_driver_sql(build_query())\n")
    hits = check_file(path)
    assert len(hits) == 1
    assert "exec_driver_sql()" in hits[0]


def test_executescript_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, "conn.executescript(contents)\n")
    assert len(check_file(path)) == 1


def test_one_message_per_line_for_nested_calls(tmp_path: Path) -> None:
    """op.execute(text(...)) is one violation at one place, not two."""
    path = write(tmp_path, 'op.execute(text("DROP TABLE users"))\n')
    assert len(check_file(path)) == 1


def test_non_sql_variable_does_not_trigger(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'payload = {"id": 1}\ntask.execute(payload)\n',
    )
    assert check_file(path) == []


def test_orm_select_passed_to_execute_is_clean(tmp_path: Path) -> None:
    path = write(tmp_path, "session.execute(select(User).where(User.id == 1))\n")
    assert check_file(path) == []


def test_string_valued_names_tracks_assignments(tmp_path: Path) -> None:
    tree = ast.parse('a = "x"\nb: str = "y"\nc = 3\n')
    assert string_valued_names(tree) == {"a", "b"}


# Adversarial review: gaps found in the round-2 checker.


def test_qualified_op_execute_is_detected(tmp_path: Path) -> None:
    """`op` may be reached through an attribute chain, not only a bare name."""
    path = write(
        tmp_path,
        "alembic.op.execute(build_sql())\nself.op.execute(build_sql())\n",
    )
    hits = check_file(path)
    assert len(hits) == 2
    assert "alembic.op.execute()" in hits[0]
    assert "self.op.execute()" in hits[1]


def test_name_rebound_to_non_string_is_not_flagged(tmp_path: Path) -> None:
    """A name that once held a string but was rebound is not a SQL argument."""
    path = write(
        tmp_path,
        'query = "SELECT 1"\nquery = select(User)\nsession.execute(query)\n',
    )
    assert check_file(path) == []


def test_two_violations_on_one_line_are_both_reported(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'cursor.execute("SELECT 1"); cursor.execute("DROP TABLE users")\n',
    )
    assert len(check_file(path)) == 2


def test_allow_marker_suppresses_a_violation(tmp_path: Path) -> None:
    path = write(tmp_path, 'legacy.execute("SELECT 1")  # raw-sql: allow\n')
    assert check_file(path) == []


def test_allow_marker_works_on_a_multiline_call(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'legacy.execute(  # raw-sql: allow\n    "SELECT 1"\n)\n',
    )
    assert check_file(path) == []


def test_hits_are_ordered_by_line_number(tmp_path: Path) -> None:
    """Sorting must be numeric, not lexical: line 10 comes after line 2."""
    body = "\n".join(f'cursor.execute("SELECT {i}")' for i in range(1, 12))
    path = write(tmp_path, body + "\n")
    hits = check_file(path)
    assert len(hits) == 11
    assert ":2:" in hits[1]
    assert ":11:" in hits[10]
