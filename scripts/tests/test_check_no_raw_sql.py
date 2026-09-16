"""Tests for the AST-based raw-SQL check."""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from check_no_raw_sql import check_file  # noqa: E402


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
