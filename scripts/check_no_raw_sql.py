#!/usr/bin/env python3
"""Fail if the given directories contain hand-written SQL.

Database access must go through the ORM only. This parses each file with `ast`
so calls that span several lines are caught just like single-line ones.

Rules are evaluated most-specific first. Some methods are raw SQL whatever they
are handed (`op.execute`, `exec_driver_sql`); others depend on the argument
(`execute("SELECT ...")` is SQL, `execute(select(User))` is the ORM).

A line the check gets wrong can be exempted with a `raw-sql: allow` comment.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

# Raw SQL regardless of what is passed - there is no ORM form of these.
UNCONDITIONAL_METHODS = {"exec_driver_sql", "executescript"}
# SQL only when handed a SQL string; `session.execute(select(User))` is fine.
ARG_SENSITIVE_METHODS = {"execute", "executemany"}
# SQLAlchemy's raw-SQL constructor, bare or qualified (`sa.text`, `sqlalchemy.text`).
SQL_TEXT_FUNCTIONS = {"text"}
ALLOW_MARKER = "raw-sql: allow"


def _dotted_name(node: ast.expr) -> str | None:
    """Return `a.b.c` for a Name/Attribute chain, else None."""
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        base = _dotted_name(node.value)
        return f"{base}.{node.attr}" if base else None
    return None


def _callee(func: ast.expr) -> tuple[str | None, str]:
    """Return (dotted receiver or None, called name) for a call target."""
    if isinstance(func, ast.Attribute):
        return _dotted_name(func.value), func.attr
    if isinstance(func, ast.Name):
        return None, func.id
    return None, ""


def _is_alembic_op(owner: str | None) -> bool:
    """True for `op`, `alembic.op`, `self.op` - any receiver ending in `op`."""
    return owner is not None and (owner == "op" or owner.endswith(".op"))


def _is_string_literal(node: ast.expr | None) -> bool:
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str)
    if isinstance(node, ast.JoinedStr):  # f-string
        return True
    if isinstance(node, ast.BinOp):  # "SELECT " + table, "SELECT %s" % x
        return _is_string_literal(node.left) or _is_string_literal(node.right)
    return False


def _is_text_call(node: ast.expr | None) -> bool:
    """True for `text(...)`, `sa.text(...)`, `sqlalchemy.text(...)`."""
    if not isinstance(node, ast.Call):
        return False
    _, name = _callee(node.func)
    return name in SQL_TEXT_FUNCTIONS


def string_valued_names(tree: ast.AST) -> set[str]:
    """Names bound to a string literal and never rebound to anything else.

    Catches `sql = "DELETE FROM users"; cursor.execute(sql)`. A name that is
    also assigned a non-string somewhere is dropped, so an ORM statement held
    in a name that once held a string is not reported.
    """
    strings: set[str] = set()
    others: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign):
            targets, value = node.targets, node.value
        elif isinstance(node, ast.AnnAssign) and node.value is not None:
            targets, value = [node.target], node.value
        else:
            continue
        bucket = strings if _is_string_literal(value) else others
        for target in targets:
            if isinstance(target, ast.Name):
                bucket.add(target.id)
    return strings - others


def _is_sql_argument(node: ast.expr | None, string_names: set[str]) -> bool:
    if _is_string_literal(node):
        return True
    if isinstance(node, ast.Name) and node.id in string_names:
        return True
    return _is_text_call(node)


def _describe(node: ast.Call, string_names: set[str]) -> str | None:
    owner, name = _callee(node.func)
    first_arg = node.args[0] if node.args else None
    label = f"{owner}.{name}" if owner else name

    # Most specific first: these are raw SQL whatever the argument is, so they
    # must be tested before the argument-sensitive rule can return early.
    if name in UNCONDITIONAL_METHODS:
        return f"{label}() - always raw SQL"
    if name == "execute" and _is_alembic_op(owner):
        return f"{label}() - always raw SQL"

    if name in ARG_SENSITIVE_METHODS and isinstance(node.func, ast.Attribute):
        if _is_sql_argument(first_arg, string_names):
            return f"{label}() with a SQL string"
        return None

    if name in SQL_TEXT_FUNCTIONS and _is_sql_argument(first_arg, string_names):
        return f"{label}() with a SQL string"

    if name == "cursor" and not node.args:
        return f"{label}()"

    return None


def _parents(tree: ast.AST) -> dict[int, ast.AST]:
    return {id(child): node for node in ast.walk(tree) for child in ast.iter_child_nodes(node)}


def _allowed(node: ast.Call, lines: list[str]) -> bool:
    """True if any line of the call carries the allow marker."""
    last = getattr(node, "end_lineno", node.lineno) or node.lineno
    return any(ALLOW_MARKER in line for line in lines[node.lineno - 1 : last])


def check_file(path: Path) -> list[str]:
    """Return one message per raw-SQL usage found in `path`."""
    source = path.read_text(encoding="utf-8")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return [f"{path}:{exc.lineno or 0}: could not parse ({exc.msg})"]

    lines = source.splitlines()
    string_names = string_valued_names(tree)
    parents = _parents(tree)
    reported: set[int] = set()
    hits: list[tuple[int, str]] = []

    # ast.walk is breadth-first, so an enclosing call is seen before the call it
    # wraps; skipping nodes nested in a reported one keeps `op.execute(text(...))`
    # to a single message without collapsing unrelated calls on the same line.
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        if _enclosed_by(node, parents, reported):
            continue
        what = _describe(node, string_names)
        if what and not _allowed(node, lines):
            reported.add(id(node))
            hits.append((node.lineno, f"{path}:{node.lineno}: {what}"))

    return [message for _, message in sorted(hits)]


def _enclosed_by(node: ast.AST, parents: dict[int, ast.AST], reported: set[int]) -> bool:
    current = parents.get(id(node))
    while current is not None:
        if id(current) in reported:
            return True
        current = parents.get(id(current))
    return False


def check_paths(dirs: list[Path]) -> list[str]:
    hits = []
    for directory in dirs:
        for path in sorted(directory.rglob("*.py")):
            hits.extend(check_file(path))
    return hits


def main(argv: list[str]) -> int:
    dirs = [Path(a) for a in argv if Path(a).is_dir()]
    if not dirs:
        print("no directories to check, skipping")
        return 0

    hits = check_paths(dirs)
    if hits:
        print("Hand-written SQL found (forbidden - use the ORM instead):", file=sys.stderr)
        for hit in hits:
            print(f"  {hit}", file=sys.stderr)
        print(f"If a line is a false positive, mark it with `# {ALLOW_MARKER}`.", file=sys.stderr)
        return 1

    print("no raw SQL found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
