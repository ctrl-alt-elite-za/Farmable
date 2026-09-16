#!/usr/bin/env python3
"""Fail if the given directories contain hand-written SQL.

Database access must go through the ORM only. This parses each file with `ast`
so calls that span several lines are caught just like single-line ones.

Rules are evaluated most-specific first. Some methods are raw SQL whatever they
are handed (`op.execute`, `exec_driver_sql`); others depend on the argument
(`execute("SELECT ...")` is SQL, `execute(select(User))` is the ORM).

A name is only treated as SQL when the binding that actually reaches the call
says so: bindings are tracked per scope and in source order, so an unrelated
function reusing the name, or a later reassignment, does not leak either way.

A line the check gets wrong can be exempted with a `raw-sql: allow` comment.
"""

from __future__ import annotations

import ast
import re
import sys
from pathlib import Path

# Raw SQL regardless of what is passed - there is no ORM form of these.
UNCONDITIONAL_METHODS = {"exec_driver_sql", "executescript"}
# SQL only when handed a SQL string; `session.execute(select(User))` is fine.
ARG_SENSITIVE_METHODS = {"execute", "executemany"}
# SQLAlchemy's raw-SQL constructor, bare or qualified (`sa.text`, `sqlalchemy.text`).
SQL_TEXT_FUNCTIONS = {"text"}
ALLOW_MARKER = "raw-sql: allow"

# A string is only SQL if it reads as a statement. Without this, `runner.execute("ls -la")`
# and `task.execute("nightly-report")` are reported, which is a guardrail blocking
# correct code.
SQL_STATEMENT = re.compile(
    r"^\s*(?:--[^\n]*\n\s*)*"
    r"(select|insert|update|delete|create|drop|alter|truncate|with|grant|revoke|merge|replace)\b",
    re.IGNORECASE,
)

SCOPE_NODES = (ast.FunctionDef, ast.AsyncFunctionDef, ast.Lambda, ast.ClassDef, ast.Module)


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


def _literal_chunks(node: ast.expr | None) -> list[str]:
    """Every string literal reachable in an expression, outermost first."""
    if isinstance(node, ast.Constant):
        return [node.value] if isinstance(node.value, str) else []
    if isinstance(node, ast.JoinedStr):  # f-string
        return [chunk for value in node.values for chunk in _literal_chunks(value)]
    if isinstance(node, ast.FormattedValue):
        return []
    if isinstance(node, ast.NamedExpr):  # cursor.execute(sql := "DROP TABLE x")
        return _literal_chunks(node.value)
    if isinstance(node, ast.BinOp):  # "SELECT " + table, "SELECT %s" % args
        return _literal_chunks(node.left) + _literal_chunks(node.right)
    return []


def looks_like_sql(node: ast.expr | None) -> bool:
    """True if a literal in this expression reads as a SQL statement."""
    return any(SQL_STATEMENT.match(chunk) for chunk in _literal_chunks(node))


class Scope:
    """Name bindings for one lexical scope, kept in source order."""

    def __init__(self, parent: Scope | None) -> None:
        self.parent = parent
        self.bindings: dict[str, list[tuple[int, bool]]] = {}

    def bind(self, name: str, lineno: int, is_sql: bool) -> None:
        self.bindings.setdefault(name, []).append((lineno, is_sql))

    def holds_sql(self, name: str, lineno: int) -> bool:
        """Does the binding reaching `lineno` hold a SQL string?

        A name bound anywhere in this scope belongs to it, so lookup stops here
        rather than falling through to an enclosing scope that reuses the name.
        """
        if name in self.bindings:
            earlier = [(line, sql) for line, sql in self.bindings[name] if line <= lineno]
            return earlier[-1][1] if earlier else False
        return self.parent.holds_sql(name, lineno) if self.parent else False


def _bound_names(target: ast.expr) -> list[str]:
    if isinstance(target, ast.Name):
        return [target.id]
    if isinstance(target, ast.Tuple | ast.List):
        return [name for element in target.elts for name in _bound_names(element)]
    return []


class _Collector(ast.NodeVisitor):
    """Walks the tree building per-scope bindings and a list of calls."""

    def __init__(self) -> None:
        self.scope = Scope(None)
        self.calls: list[tuple[ast.Call, Scope]] = []

    def _in_new_scope(self, node: ast.AST) -> None:
        outer, self.scope = self.scope, Scope(self.scope)
        self.generic_visit(node)
        self.scope = outer

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._visit_function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._visit_function(node)

    def _visit_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        outer, self.scope = self.scope, Scope(self.scope)
        args = node.args
        for arg in [*args.posonlyargs, *args.args, *args.kwonlyargs]:
            self.scope.bind(arg.arg, node.lineno, False)
        for maybe in (args.vararg, args.kwarg):
            if maybe is not None:
                self.scope.bind(maybe.arg, node.lineno, False)
        self.generic_visit(node)
        self.scope = outer

    def visit_Lambda(self, node: ast.Lambda) -> None:
        self._in_new_scope(node)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self._in_new_scope(node)

    def visit_Assign(self, node: ast.Assign) -> None:
        is_sql = looks_like_sql(node.value)
        for target in node.targets:
            for name in _bound_names(target):
                self.scope.bind(name, node.lineno, is_sql)
        self.generic_visit(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        if node.value is not None:
            for name in _bound_names(node.target):
                self.scope.bind(name, node.lineno, looks_like_sql(node.value))
        self.generic_visit(node)

    def visit_AugAssign(self, node: ast.AugAssign) -> None:
        # An append keeps whatever the name already held, so `sql = "SELECT ..."`
        # followed by `sql += " WHERE ..."` stays SQL.
        appended = looks_like_sql(node.value)
        for name in _bound_names(node.target):
            already = self.scope.holds_sql(name, node.lineno)
            self.scope.bind(name, node.lineno, already or appended)
        self.generic_visit(node)

    def visit_NamedExpr(self, node: ast.NamedExpr) -> None:
        for name in _bound_names(node.target):
            self.scope.bind(name, node.lineno, looks_like_sql(node.value))
        self.generic_visit(node)

    def visit_For(self, node: ast.For) -> None:
        for name in _bound_names(node.target):
            self.scope.bind(name, node.lineno, False)
        self.generic_visit(node)

    def visit_Call(self, node: ast.Call) -> None:
        self.calls.append((node, self.scope))
        self.generic_visit(node)


def _is_text_call(node: ast.expr | None) -> bool:
    """True for `text(...)`, `sa.text(...)`, `sqlalchemy.text(...)`."""
    if not isinstance(node, ast.Call):
        return False
    _, name = _callee(node.func)
    return name in SQL_TEXT_FUNCTIONS


def _is_sql_argument(node: ast.expr | None, scope: Scope, lineno: int) -> bool:
    if looks_like_sql(node):
        return True
    if isinstance(node, ast.Name) and scope.holds_sql(node.id, lineno):
        return True
    return _is_text_call(node)


def _describe(node: ast.Call, scope: Scope) -> str | None:
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
        if _is_sql_argument(first_arg, scope, node.lineno):
            return f"{label}() with a SQL string"
        return None

    if name in SQL_TEXT_FUNCTIONS and _is_sql_argument(first_arg, scope, node.lineno):
        return f"{label}() with a SQL string"

    if name == "cursor" and not node.args:
        return f"{label}()"

    return None


def _parents(tree: ast.AST) -> dict[int, ast.AST]:
    return {id(child): node for node in ast.walk(tree) for child in ast.iter_child_nodes(node)}


def _enclosed_by(node: ast.AST, parents: dict[int, ast.AST], reported: set[int]) -> bool:
    current = parents.get(id(node))
    while current is not None:
        if id(current) in reported:
            return True
        current = parents.get(id(current))
    return False


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
    collector = _Collector()
    collector.visit(tree)
    parents = _parents(tree)
    reported: set[int] = set()
    hits: list[tuple[int, str]] = []

    # Outermost call first, so skipping calls nested inside a reported one keeps
    # `op.execute(text(...))` to a single message without collapsing unrelated
    # calls that merely share a line.
    def position(pair: tuple[ast.Call, Scope]) -> tuple[int, int]:
        return pair[0].lineno, pair[0].col_offset

    for node, scope in sorted(collector.calls, key=position):
        if _enclosed_by(node, parents, reported):
            continue
        what = _describe(node, scope)
        if what and not _allowed(node, lines):
            reported.add(id(node))
            hits.append((node.lineno, f"{path}:{node.lineno}: {what}"))

    return [message for _, message in sorted(hits)]


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
