#!/usr/bin/env python3
"""Fail if the given directories contain hand-written SQL.

Database access must go through the ORM only. This parses each file with `ast`
so calls that span several lines are caught just like single-line ones.

Rules are evaluated most-specific first. Some methods are raw SQL whatever they
are handed (`op.execute`, `exec_driver_sql`); others depend on the argument
(`execute("SELECT ...")` is SQL, `execute(select(User))` is the ORM).
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


def _callee_name(func: ast.expr) -> tuple[str | None, str]:
    """Return (attribute owner name or None, called name) for a call target."""
    if isinstance(func, ast.Attribute):
        owner = func.value.id if isinstance(func.value, ast.Name) else None
        return owner, func.attr
    if isinstance(func, ast.Name):
        return None, func.id
    return None, ""


def _qualified(owner: str | None, name: str) -> str:
    return f"{owner}.{name}" if owner else name


def _is_string_literal(node: ast.expr | None) -> bool:
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str)
    if isinstance(node, ast.JoinedStr):  # f-string
        return True
    if isinstance(node, ast.BinOp):  # "SELECT " + table
        return _is_string_literal(node.left) or _is_string_literal(node.right)
    return False


def _is_text_call(node: ast.expr | None) -> bool:
    """True for `text(...)`, `sa.text(...)`, `sqlalchemy.text(...)`."""
    if not isinstance(node, ast.Call):
        return False
    _, name = _callee_name(node.func)
    return name in SQL_TEXT_FUNCTIONS


def string_valued_names(tree: ast.AST) -> set[str]:
    """Names bound to a string literal anywhere in the file.

    Catches the indirection `sql = "DELETE FROM users"; cursor.execute(sql)`.
    """
    names: set[str] = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and _is_string_literal(node.value):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    names.add(target.id)
        elif isinstance(node, ast.AnnAssign) and _is_string_literal(node.value):
            if isinstance(node.target, ast.Name):
                names.add(node.target.id)
    return names


def _is_sql_argument(node: ast.expr | None, string_names: set[str]) -> bool:
    if _is_string_literal(node):
        return True
    if isinstance(node, ast.Name) and node.id in string_names:
        return True
    return _is_text_call(node)


def _describe(node: ast.Call, string_names: set[str]) -> str | None:
    owner, name = _callee_name(node.func)
    first_arg = node.args[0] if node.args else None
    label = _qualified(owner, name)

    # Most specific first: these are raw SQL whatever the argument is, so they
    # must be tested before the argument-sensitive rule can return early.
    if name in UNCONDITIONAL_METHODS:
        return f"{label}() - always raw SQL"
    if name == "execute" and owner == "op":
        return "op.execute() - always raw SQL"

    if name in ARG_SENSITIVE_METHODS and isinstance(node.func, ast.Attribute):
        if _is_sql_argument(first_arg, string_names):
            return f"{label}() with a SQL string"
        return None

    if name in SQL_TEXT_FUNCTIONS and _is_sql_argument(first_arg, string_names):
        return f"{label}() with a SQL string"

    if name == "cursor" and not node.args:
        return f"{label}()"

    return None


def check_file(path: Path) -> list[str]:
    """Return one message per raw-SQL usage found in `path`."""
    source = path.read_text(encoding="utf-8")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return [f"{path}:{exc.lineno or 0}: could not parse ({exc.msg})"]

    string_names = string_valued_names(tree)
    hits: list[str] = []
    seen_lines: set[int] = set()
    # ast.walk is breadth-first, so an outer call is described before the inner
    # one it wraps; one message per line keeps `op.execute(text("..."))` to one.
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and node.lineno not in seen_lines:
            what = _describe(node, string_names)
            if what:
                seen_lines.add(node.lineno)
                hits.append(f"{path}:{node.lineno}: {what}")
    return sorted(hits)


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
        return 1

    print("no raw SQL found")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
