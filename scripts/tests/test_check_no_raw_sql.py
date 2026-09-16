"""Tests for the AST-based raw-SQL check."""

import ast
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from check_no_raw_sql import check_file, looks_like_sql  # noqa: E402


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


def test_looks_like_sql_distinguishes_statements_from_plain_strings() -> None:
    assert looks_like_sql(ast.parse('"SELECT 1"', mode="eval").body)
    assert looks_like_sql(ast.parse('"  delete from users"', mode="eval").body)
    assert not looks_like_sql(ast.parse('"ls -la"', mode="eval").body)
    assert not looks_like_sql(ast.parse('"nightly-report"', mode="eval").body)


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


# Review round 3: name tracking must respect scope and source order.


def test_name_reused_in_another_function_is_not_flagged(tmp_path: Path) -> None:
    """A string bound in one function must not leak into another's scope."""
    path = write(
        tmp_path,
        "def a():\n"
        '    query = "label"\n'
        "\n"
        "def b(session):\n"
        "    query = select(User)\n"
        "    session.execute(query)\n",
    )
    assert check_file(path) == []


def test_reassignment_before_an_orm_execute_is_not_flagged(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'query = "label"\nquery = select(User)\nsession.execute(query)\n',
    )
    assert check_file(path) == []


def test_non_sql_strings_to_unrelated_execute_are_not_flagged(tmp_path: Path) -> None:
    """A guardrail that blocks `runner.execute("ls -la")` blocks correct code."""
    path = write(
        tmp_path,
        'cmd = "ls -la"\nrunner.execute(cmd)\ntask.execute("nightly-report")\n',
    )
    assert check_file(path) == []


def test_sql_in_one_function_is_caught_despite_reuse_elsewhere(tmp_path: Path) -> None:
    """The mirror case: name reuse must not hide real SQL in another scope."""
    path = write(
        tmp_path,
        "def f(session):\n"
        "    query = select(User)\n"
        "    session.execute(query)\n"
        "\n"
        "def g(cursor):\n"
        '    query = "DELETE FROM users"\n'
        "    cursor.execute(query)\n",
    )
    hits = check_file(path)
    assert len(hits) == 1
    assert ":7:" in hits[0]


def test_binding_after_the_call_does_not_reach_it(tmp_path: Path) -> None:
    """Order matters: SQL assigned after the call is not what the call used."""
    path = write(
        tmp_path,
        "def f(session):\n"
        "    query = select(User)\n"
        "    session.execute(query)\n"
        '    query = "SELECT 1"\n',
    )
    assert check_file(path) == []


def test_parameter_shadows_a_module_level_sql_string(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'query = "SELECT * FROM users"\n'
        "\n"
        "def f(session, query):\n"
        "    session.execute(query)\n",
    )
    assert check_file(path) == []


def test_module_level_sql_reaches_a_function_that_does_not_rebind(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'QUERY = "SELECT * FROM users"\n' "\n" "def f(cursor):\n" "    cursor.execute(QUERY)\n",
    )
    assert len(check_file(path)) == 1


def test_sql_appended_with_augmented_assignment_is_detected(tmp_path: Path) -> None:
    """`sql += " WHERE ..."` appends to SQL; it does not make it not-SQL."""
    path = write(
        tmp_path,
        "def f(cursor):\n"
        '    sql = "SELECT * FROM users"\n'
        '    sql += " WHERE active = 1"\n'
        "    cursor.execute(sql)\n",
    )
    assert len(check_file(path)) == 1


def test_walrus_bound_sql_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'cursor.execute(sql := "DROP TABLE users")\n')
    assert len(check_file(path)) == 1


def test_sql_in_both_branches_of_a_conditional_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(cursor, flag):\n"
        "    if flag:\n"
        '        q = "SELECT 1"\n'
        "    else:\n"
        '        q = "SELECT 2"\n'
        "    cursor.execute(q)\n",
    )
    assert len(check_file(path)) == 1


def test_appending_to_a_non_sql_string_stays_clean(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(runner):\n" '    cmd = "ls"\n' '    cmd += " -la"\n' "    runner.execute(cmd)\n",
    )
    assert check_file(path) == []


# Review round 4: control flow, and text() regardless of contents.


def test_sql_in_the_first_branch_is_detected(tmp_path: Path) -> None:
    """Line order is not control flow: the later else must not mask the if."""
    path = write(
        tmp_path,
        "def f(session, use_raw_sql):\n"
        "    if use_raw_sql:\n"
        '        query = "SELECT * FROM users"\n'
        "    else:\n"
        "        query = select(User)\n"
        "\n"
        "    session.execute(query)\n",
    )
    hits = check_file(path)
    assert len(hits) == 1
    assert ":7:" in hits[0]


def test_sql_in_a_later_branch_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(session, flag):\n"
        "    if flag:\n"
        "        query = select(User)\n"
        "    else:\n"
        '        query = "SELECT * FROM users"\n'
        "    session.execute(query)\n",
    )
    assert len(check_file(path)) == 1


def test_sql_in_an_elif_chain_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(session, mode):\n"
        "    if mode == 1:\n"
        '        query = "SELECT * FROM users"\n'
        "    elif mode == 2:\n"
        "        query = select(User)\n"
        "    else:\n"
        "        query = select(Farm)\n"
        "    session.execute(query)\n",
    )
    assert len(check_file(path)) == 1


def test_sql_in_a_try_block_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(session):\n"
        "    try:\n"
        '        query = "DELETE FROM users"\n'
        "    except KeyError:\n"
        "        query = select(User)\n"
        "    session.execute(query)\n",
    )
    assert len(check_file(path)) == 1


def test_sql_assigned_in_a_loop_body_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(session, rows):\n"
        "    query = select(User)\n"
        "    for row in rows:\n"
        '        query = "SELECT 1"\n'
        "    session.execute(query)\n",
    )
    assert len(check_file(path)) == 1


def test_unconditional_rebind_after_a_branch_clears_it(tmp_path: Path) -> None:
    """A binding that definitely runs supersedes the conditional ones before it."""
    path = write(
        tmp_path,
        "def f(session, flag):\n"
        "    if flag:\n"
        '        query = "SELECT * FROM users"\n'
        "    query = select(User)\n"
        "    session.execute(query)\n",
    )
    assert check_file(path) == []


def test_vacuum_is_recognised_as_sql(tmp_path: Path) -> None:
    path = write(tmp_path, 'conn.execute("VACUUM")\n')
    assert len(check_file(path)) == 1


def test_set_statement_is_recognised_as_sql(tmp_path: Path) -> None:
    path = write(tmp_path, 'conn.execute("SET search_path TO public")\n')
    assert len(check_file(path)) == 1


def test_text_is_raw_sql_whatever_it_contains(tmp_path: Path) -> None:
    """The rule forbids hand-written SQL, not only recognised statements."""
    path = write(
        tmp_path,
        'stmt = text("SET search_path TO public")\nsession.execute(stmt)\n',
    )
    hits = check_file(path)
    assert len(hits) == 2
    assert "text() - always raw SQL" in hits[0]


def test_text_with_an_unrecognised_body_is_still_raw_sql(tmp_path: Path) -> None:
    path = write(tmp_path, "session.execute(sa.text(build_fragment()))\n")
    assert len(check_file(path)) == 1


def test_prose_starting_with_an_ambiguous_keyword_stays_clean(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'runner.execute("set up the environment")\nrunner.execute("show me the report")\n',
    )
    assert check_file(path) == []
