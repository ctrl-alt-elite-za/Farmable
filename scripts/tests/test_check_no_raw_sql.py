"""Tests for the AST-based raw-SQL check."""

import ast
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from check_no_raw_sql import (  # noqa: E402
    check_file,
    check_paths,
    looks_like_sql,
    main,
)


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


# Adversarial review of round 4: reachability, expression forms, prose.


def test_binding_in_an_exclusive_branch_does_not_reach_the_call(tmp_path: Path) -> None:
    """A call in the `else` cannot be reached by a binding in the `if`."""
    path = write(
        tmp_path,
        "def f(session, flag):\n"
        "    query = select(User)\n"
        "    if flag:\n"
        '        query = "SELECT 1"\n'
        "    else:\n"
        "        session.execute(query)\n",
    )
    assert check_file(path) == []


def test_call_in_the_same_branch_as_the_sql_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(session, flag):\n"
        "    if flag:\n"
        '        query = "SELECT 1"\n'
        "        session.execute(query)\n"
        "    else:\n"
        "        query = select(User)\n",
    )
    assert len(check_file(path)) == 1


def test_sql_in_a_conditional_expression_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(session, flag):\n"
        '    query = "SELECT * FROM users" if flag else select(User)\n'
        "    session.execute(query)\n",
    )
    assert len(check_file(path)) == 1


def test_text_in_a_conditional_expression_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(session, flag):\n"
        "    query = text(build()) if flag else select(User)\n"
        "    session.execute(query)\n",
    )
    assert len(check_file(path)) >= 1


def test_sql_behind_a_boolean_fallback_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        "def f(cursor, override):\n"
        '    query = override or "DELETE FROM users"\n'
        "    cursor.execute(query)\n",
    )
    assert len(check_file(path)) == 1


def test_sql_in_a_match_case_is_detected(tmp_path: Path) -> None:
    """`match` arms are branches; the last case must not mask an earlier one."""
    path = write(
        tmp_path,
        "def f(session, mode):\n"
        "    match mode:\n"
        "        case 1:\n"
        '            query = "SELECT * FROM users"\n'
        "        case _:\n"
        "            query = select(User)\n"
        "    session.execute(query)\n",
    )
    hits = check_file(path)
    assert len(hits) == 1
    assert ":7:" in hits[0]


def test_prose_containing_sql_clause_words_stays_clean(tmp_path: Path) -> None:
    """A clause word anywhere in a sentence is not a SQL statement."""
    path = write(
        tmp_path,
        'runner.execute("show the file as backup")\n'
        'runner.execute("copy the report to the archive")\n'
        'runner.execute("set up the environment")\n',
    )
    assert check_file(path) == []


def test_uppercase_ambiguous_keyword_is_sql(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'conn.execute("SET LOCAL statement_timeout = 5")\nconn.execute("BEGIN TRANSACTION")\n',
    )
    assert len(check_file(path)) == 2


def test_terminated_statement_is_sql_whatever_its_case(tmp_path: Path) -> None:
    path = write(tmp_path, 'conn.execute("commit;")\n')
    assert len(check_file(path)) == 1


def test_lowercase_cte_is_detected(tmp_path: Path) -> None:
    """`with ... select ...` opens with an ambiguous word but is a statement."""
    path = write(
        tmp_path,
        'cursor.execute("with recent as (select 1) select * from recent")\n',
    )
    assert len(check_file(path)) == 1


def test_formatted_multiline_sql_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'cursor.execute("""\n'
        "    with recent as (select id from users)\n"
        "    select * from recent\n"
        '""")\n',
    )
    assert len(check_file(path)) == 1


# Adversarial review of round 5: recognition must not widen into prose.


def test_plain_formatted_sql_is_detected(tmp_path: Path) -> None:
    """A leading newline and indent is how multi-line SQL is actually written."""
    path = write(
        tmp_path,
        'cursor.execute("""\n    select *\n    from users\n""")\n',
    )
    assert len(check_file(path)) == 1


def test_prose_with_a_sql_verb_later_stays_clean(tmp_path: Path) -> None:
    """An ambiguous opener plus a verb somewhere after it is not a statement."""
    path = write(
        tmp_path,
        'runner.execute("show the report and update the archive")\n'
        'runner.execute("copy the file and create a backup")\n'
        'runner.execute("set the flag and drop the cache")\n'
        'runner.execute("use the select box on the form")\n',
    )
    assert check_file(path) == []


def test_shell_script_argument_stays_clean(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'runner.execute("""\nset -e\nupdate-config --now\n""")\n',
    )
    assert check_file(path) == []


def test_leading_comment_before_a_statement_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'cursor.execute("-- active users\\nselect 1")\n')
    assert len(check_file(path)) == 1


def test_paths_and_commands_opening_with_a_sql_verb_stay_clean(tmp_path: Path) -> None:
    """A hyphen or dot ends a word, so `\\b` alone called these statements."""
    path = write(
        tmp_path,
        'runner.execute("delete-me.txt")\n'
        'runner.execute("update-config --now")\n'
        'runner.execute("drop.sh")\n'
        'runner.execute("truncate-logs")\n',
    )
    assert check_file(path) == []


def test_block_comment_before_a_statement_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'cursor.execute("/* active users */ select 1")\n')
    assert len(check_file(path)) == 1


def test_recursive_cte_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'cursor.execute("WITH RECURSIVE tree AS (select 1) select * from tree")\n',
    )
    assert len(check_file(path)) == 1


def test_words_merely_starting_with_a_verb_stay_clean(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'runner.execute("SELECTION criteria")\nrunner.execute("insertion point")\n',
    )
    assert check_file(path) == []


# Adversarial review of round 6: robustness and recognition gaps.


def test_deeply_nested_expression_does_not_abort_the_run(tmp_path: Path) -> None:
    """A file too deep to analyse is named; it must not discard other hits."""
    (tmp_path / "aaa_violation.py").write_text(
        'cursor.execute("DELETE FROM users")\n', encoding="utf-8"
    )
    (tmp_path / "deep.py").write_text(
        "q = " + " + ".join(['"x"'] * 3000) + "\ncursor.execute(q)\n", encoding="utf-8"
    )
    hits = check_paths([tmp_path]).hits
    violations = [hit for hit in hits if "aaa_violation.py" in hit]
    unanalysable = [hit for hit in hits if "deep.py" in hit]
    assert len(violations) == 1
    assert "cursor.execute() with a SQL string" in violations[0]
    assert len(unanalysable) == 1
    assert "could not be analysed" in unanalysable[0]


def test_long_concatenated_sql_is_still_read(tmp_path: Path) -> None:
    """The literal walk is iterative, so ordinary long concatenations work."""
    body = 'sql = "SELECT 1" ' + "".join(f'+ " x{i}" ' for i in range(400))
    path = write(tmp_path, f"{body}\ncursor.execute(sql)\n")
    assert len(check_file(path)) == 1


def test_cte_with_a_column_list_is_detected(tmp_path: Path) -> None:
    path = write(
        tmp_path,
        'cursor.execute("with cte(col1, col2) as (select 1) select 1")\n',
    )
    assert len(check_file(path)) == 1


def test_select_without_a_space_is_detected(tmp_path: Path) -> None:
    path = write(tmp_path, 'cursor.execute("SELECT*FROM users")\n')
    assert len(check_file(path)) == 1


def test_shell_globs_opening_with_a_verb_stay_clean(tmp_path: Path) -> None:
    """Allowing `*` after any verb would report `drop*.sh` and `delete*.bak`."""
    path = write(
        tmp_path,
        'runner.execute("drop*.sh")\n'
        'runner.execute("delete*.bak")\n'
        'runner.execute("update*")\n',
    )
    assert check_file(path) == []


def test_undecodable_file_does_not_hide_other_findings(tmp_path: Path) -> None:
    """A stray byte must not end the run; UnicodeDecodeError is not an OSError."""
    (tmp_path / "aaa_ok.py").write_text('cursor.execute("DROP TABLE t")\n', encoding="utf-8")
    (tmp_path / "latin.py").write_bytes(b'x = "\xff\xfe"\ncursor.execute("DELETE FROM users")\n')
    hits = check_paths([tmp_path]).hits
    assert any("aaa_ok.py" in hit for hit in hits)
    assert any("latin.py" in hit for hit in hits)


def test_an_unanalysable_file_cannot_be_waived_in_file(tmp_path: Path) -> None:
    """A file-level marker was a bypass: pad a file, waive it, smuggle SQL."""
    (tmp_path / "smuggle.py").write_text(
        "# raw-sql: allow-file\n"
        'cursor.execute("DROP TABLE users")\n'
        "pad = " + " + ".join(['"x"'] * 3000) + "\n",
        encoding="utf-8",
    )
    hits = check_paths([tmp_path]).hits
    assert len(hits) == 1
    assert "could not be analysed" in hits[0]


def test_per_call_marker_still_waives_one_call(tmp_path: Path) -> None:
    """The per-call marker is bounded, so it stays."""
    path = write(
        tmp_path,
        'legacy.execute("SELECT 1")  # raw-sql: allow\ncursor.execute("DROP TABLE t")\n',
    )
    hits = check_file(path)
    assert len(hits) == 1
    assert ":2:" in hits[0]


def test_non_sql_strings_are_why_recognition_cannot_be_dropped(tmp_path: Path) -> None:
    """Pins the Track 3 result: flagging any string literal breaks valid code.

    If this ever becomes acceptable, the keyword recognition in
    `looks_like_sql` can go and the checker gets much simpler.
    """
    path = write(
        tmp_path,
        'runner.execute("ls -la")\ntask.execute("nightly-report")\n',
    )
    assert check_file(path) == []


# The invariant. Every defect that made this check report success while
# examining nothing arrived by a different mechanism - a crash, a file-level
# waiver, a mistyped path. Example tests cannot catch the next mechanism, so
# assert the property instead: a clean verdict means every file was examined.

PATHOLOGICAL: dict[str, bytes] = {
    "clean.py": b"session.execute(select(User))\n",
    "violation.py": b'cursor.execute("DROP TABLE users")\n',
    "syntax_error.py": b"def broken(:\n",
    "undecodable.py": b'x = "\xff\xfe"\n',
    "waiver_attempt.py": b'# raw-sql: allow-file\ncursor.execute("DELETE FROM t")\n',
    "deep.py": b"q = " + b" + ".join([b'"x"'] * 3000) + b"\n",
    "empty.py": b"",
}


def test_every_file_is_examined_or_excluded(tmp_path: Path) -> None:
    """No input may leave a file neither analysed nor deliberately excluded."""
    for name, content in PATHOLOGICAL.items():
        (tmp_path / name).write_bytes(content)
    result = check_paths([tmp_path])
    assert result.seen == len(PATHOLOGICAL)
    assert result.unexamined == 0


def test_a_clean_verdict_requires_having_examined_everything(tmp_path: Path) -> None:
    """Exit 0 must mean 'checked and found nothing', never 'did not look'."""
    for name, content in PATHOLOGICAL.items():
        (tmp_path / name).write_bytes(content)
    result = check_paths([tmp_path])
    assert result.hits, "pathological corpus must not come back clean"
    assert main([str(tmp_path)]) == 1


def test_no_single_file_can_suppress_another(tmp_path: Path) -> None:
    """Whatever one file does, a violation in another is still reported."""
    (tmp_path / "violation.py").write_bytes(b'cursor.execute("DROP TABLE users")\n')
    for name, content in PATHOLOGICAL.items():
        if name == "clean.py":
            continue
        neighbour = tmp_path / f"neighbour_{name}"
        neighbour.write_bytes(content)
        result = check_paths([tmp_path])
        assert any("violation.py" in hit for hit in result.hits), f"hidden by {name}"
        neighbour.unlink()


def test_a_path_that_is_not_a_directory_is_an_error(tmp_path: Path) -> None:
    assert main([str(tmp_path / "nope")]) == 2


def test_an_unknown_option_is_an_error(tmp_path: Path) -> None:
    assert main(["--bogus", str(tmp_path)]) == 2


def test_exclusion_is_counted_not_silent(tmp_path: Path) -> None:
    (tmp_path / "deep.py").write_bytes(PATHOLOGICAL["deep.py"])
    result = check_paths([tmp_path], ["deep.py"])
    assert result.excluded == 1
    assert result.hits == []
