"""Tests for the AST-based raw-SQL check."""

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
    tree = __import__("ast").parse('a = "x"\nb: str = "y"\nc = 3\n')
    assert string_valued_names(tree) == {"a", "b"}
