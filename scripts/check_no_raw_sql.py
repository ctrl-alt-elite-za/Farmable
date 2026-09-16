#!/usr/bin/env python3
"""Fail if the given directories contain hand-written SQL.

Database access must go through the ORM only. This parses each file with `ast`
so calls that span several lines are caught just like single-line ones.
"""

from __future__ import annotations

import ast
import sys
from pathlib import Path

# Methods that take raw SQL as their first argument.
EXECUTE_METHODS = {"execute", "executemany", "executescript", "exec_driver_sql"}
# Bare functions that wrap a SQL string.
SQL_FUNCTIONS = {"text"}


def _callee_name(func: ast.expr) -> tuple[str | None, str]:
    """Return (attribute owner name or None, called name) for a call target."""
    if isinstance(func, ast.Attribute):
        owner = func.value.id if isinstance(func.value, ast.Name) else None
        return owner, func.attr
    if isinstance(func, ast.Name):
        return None, func.id
    return None, ""


def _is_string_literal(node: ast.expr | None) -> bool:
    if isinstance(node, ast.Constant):
        return isinstance(node.value, str)
    if isinstance(node, ast.JoinedStr):  # f-string
        return True
    if isinstance(node, ast.BinOp):  # "SELECT " + table
        return _is_string_literal(node.left) or _is_string_literal(node.right)
    return False


def _describe(node: ast.Call) -> str | None:
    owner, name = _callee_name(node.func)
    first_arg = node.args[0] if node.args else None

    if name in EXECUTE_METHODS and isinstance(node.func, ast.Attribute):
        if _is_string_literal(first_arg):
            return f"{owner + '.' if owner else ''}{name}() with a SQL string literal"
        return None
    if name == "execute" and owner == "op":
        return "op.execute()"
    if name in SQL_FUNCTIONS and isinstance(node.func, ast.Name):
        if _is_string_literal(first_arg):
            return "text() with a SQL string literal"
        return None
    if name == "cursor" and not node.args:
        return f"{owner + '.' if owner else ''}cursor()"
    return None


def check_file(path: Path) -> list[str]:
    """Return one message per raw-SQL usage found in `path`."""
    source = path.read_text(encoding="utf-8")
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return [f"{path}:{exc.lineno or 0}: could not parse ({exc.msg})"]

    hits = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call):
            what = _describe(node)
            if what:
                hits.append(f"{path}:{node.lineno}: {what}")
    return hits


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
