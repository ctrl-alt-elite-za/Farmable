#!/usr/bin/env python3
"""Fail if the given directories contain hand-written SQL.

Database access must go through the ORM only. This parses each file with `ast`
so calls that span several lines are caught just like single-line ones.

This is one of three overlapping checks, and deliberately the narrowest. Every
route to raw SQL reachable through an import is banned by ruff's TID251 instead
(`sqlalchemy.text` and its aliases, and the DBAPI drivers), which needs no SQL
recognition and so cannot be defeated by formatting or dialect; ruff's S608
catches queries built by interpolation. What is left for this checker is the
residue that has no import to ban, because the call is a method on an object
obtained at runtime:

    conn.execute("SELECT ...")      a Connection from a session or engine
    cursor.execute(sql)             a cursor from raw_connection()
    conn.exec_driver_sql(...)       no importable name of its own
    op.execute(...)                 `op` is legitimate for the rest of Alembic

Recognising SQL in a string is unavoidable for that residue - `runner.execute(
"ls -la")` must stay clean - and is the fragile part. Keep new detection in the
import bans where possible; only add here what genuinely has no import.

Rules are evaluated most-specific first. Some methods are raw SQL whatever they
are handed (`op.execute`, `exec_driver_sql`); others depend on the argument
(`execute("SELECT ...")` is SQL, `execute(select(User))` is the ORM).

A name is only treated as SQL when the binding that actually reaches the call
says so: bindings are tracked per scope and in source order, so an unrelated
function reusing the name, or a later reassignment, does not leak either way.

A line the check gets wrong can be exempted with a `raw-sql: allow` comment. A
whole file cannot be exempted from inside itself - that was a way to smuggle SQL
past the check - so a file that defeats the parser is listed in
`[tool.check-no-raw-sql] exclude`, where review can see it.
"""

from __future__ import annotations

import ast
import re
import sys
import tomllib
from collections import deque
from fnmatch import fnmatch
from pathlib import Path, PurePosixPath, PureWindowsPath

# Raw SQL regardless of what is passed - there is no ORM form of these.
UNCONDITIONAL_METHODS = {"exec_driver_sql", "executescript"}
# SQL only when handed a SQL string; `session.execute(select(User))` is fine.
ARG_SENSITIVE_METHODS = {"execute", "executemany"}
# SQLAlchemy's raw-SQL constructor, bare or qualified (`sa.text`, `sqlalchemy.text`).
SQL_TEXT_FUNCTIONS = {"text"}
ALLOW_MARKER = "raw-sql: allow"

# A string is only SQL if it reads as a statement. Without this, `runner.execute("ls -la")`
# and `task.execute("nightly-report")` are reported, which is a guardrail blocking
# correct code. No dialect is pinned in this repo, so this covers ANSI plus the
# PostgreSQL commands Alembic and SQLAlchemy emit.
_LEADING = r"^\s*(?:(?:--[^\n]*\n|/\*[\s\S]*?\*/)\s*)*"
# Unambiguous: these words do not start an ordinary English sentence handed to a
# non-SQL `.execute()`, so the keyword alone is enough.
_STRONG = (
    "select|insert|update|delete|merge|upsert|truncate|vacuum|reindex|analyze|analyse|"
    "explain|cluster|checkpoint|rollback|savepoint|deallocate|listen|unlisten|notify|"
    "grant|revoke|pragma|refresh|create|drop|alter"
)
# Ambiguous in prose ("set up the run", "copy the file"), so these need a second
# SQL token before the string counts as a statement.
_WEAK = (
    "set|show|copy|call|do|use|lock|declare|fetch|close|prepare|reset|comment|rename|"
    "begin|commit|end|start|table|values|with|replace|attach|detach|release"
)
_CLAUSE = (
    r"\b(to|from|where|into|values|table|index|schema|view|transaction|work|isolation|"
    r"database|role|user|session|search_path|constraint|column|trigger|function|"
    r"sequence|extension|as|on|set)\b|[=;]"
)
# `.match()` anchors at position 0, so re.MULTILINE would never reach a later
# line; leading whitespace is what actually lets a formatted block through.
SQL_STATEMENT = re.compile(rf"{_LEADING}({_STRONG})(?=[\s(;]|$)", re.IGNORECASE)
# A CTE opens with the ambiguous word `with`, so match the shape of a CTE rather
# than "an ambiguous opener with a verb somewhere after it" - the latter reports
# prose such as "show the report and update the archive".
SQL_STATEMENT_CTE = re.compile(
    rf'{_LEADING}with\s+(?:recursive\s+)?[A-Za-z_"][\w".]*\s*(?:\([^)]*\))?\s*\bas\b\s*\(',
    re.IGNORECASE,
)
SQL_STATEMENT_WEAK = re.compile(
    rf"{_LEADING}({_WEAK.upper()})\b(\s|;|$)",
)
# `SELECT*FROM t` is valid but has no delimiter after the verb, so it needs its
# own shape rather than allowing `*` after every verb.
SQL_STATEMENT_STAR = re.compile(rf"{_LEADING}select\s*\*\s*from\b", re.IGNORECASE)
SQL_STATEMENT_TERMINATED = re.compile(
    rf"{_LEADING}({_WEAK})\b(?:\s+[^\s;]+){{0,6}}\s*;\s*$",
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
    """Every string literal reachable in an expression, outermost first.

    Iterative: a long concatenation nests one BinOp per term, and recursion
    here blew the stack on generated files, which aborted the whole scan.
    """
    chunks: list[str] = []
    stack: deque[ast.expr | None] = deque([node])
    while stack:
        current = stack.popleft()
        if isinstance(current, ast.Constant):
            if isinstance(current.value, str):
                chunks.append(current.value)
        elif isinstance(current, ast.JoinedStr):  # f-string
            stack.extendleft(reversed(current.values))
        elif isinstance(current, ast.FormattedValue):
            continue
        elif isinstance(current, ast.BinOp):  # "SELECT " + table, "SELECT %s" % args
            stack.extendleft([current.right, current.left])
        elif isinstance(current, ast.NamedExpr):  # execute(sql := "DROP TABLE x")
            stack.appendleft(current.value)
        elif isinstance(current, ast.IfExp):  # "SELECT 1" if flag else select(User)
            stack.extendleft([current.orelse, current.body])
        elif isinstance(current, ast.BoolOp):  # override or "SELECT 1"
            stack.extendleft(reversed(current.values))
    return chunks


def _is_sql_text(chunk: str) -> bool:
    return bool(
        SQL_STATEMENT.match(chunk)
        or SQL_STATEMENT_WEAK.match(chunk)
        or SQL_STATEMENT_TERMINATED.match(chunk)
        or SQL_STATEMENT_CTE.match(chunk)
        or SQL_STATEMENT_STAR.match(chunk)
    )


def looks_like_sql(node: ast.expr | None) -> bool:
    """True if a literal in this expression reads as a SQL statement."""
    return any(_is_sql_text(chunk) for chunk in _literal_chunks(node))


# Where a binding sits in the branch structure: one (statement, branch) pair per
# enclosing conditional. A binding on the path to a call definitely ran; one in a
# sibling branch only might have.
BranchPath = tuple[tuple[int, int], ...]


class Binding:
    __slots__ = ("lineno", "is_sql", "path")

    def __init__(self, lineno: int, is_sql: bool, path: BranchPath) -> None:
        self.lineno = lineno
        self.is_sql = is_sql
        self.path = path

    def definitely_reaches(self, path: BranchPath) -> bool:
        """True if this binding runs on every path to a call at `path`."""
        return path[: len(self.path)] == self.path

    def can_reach(self, path: BranchPath) -> bool:
        """False when the binding sits in a branch exclusive with the call's.

        Two positions are exclusive when they take different arms of the same
        statement: `if x: q = "SELECT 1"` cannot reach a call in that `if`'s
        `else`, so it must not be merged into the call's state.
        """
        for mine, theirs in zip(self.path, path, strict=False):
            if mine[0] == theirs[0] and mine[1] != theirs[1]:
                return False
        return True


class Scope:
    """Name bindings for one lexical scope, kept in source order."""

    def __init__(self, parent: Scope | None) -> None:
        self.parent = parent
        self.bindings: dict[str, list[Binding]] = {}

    def bind(self, name: str, lineno: int, is_sql: bool, path: BranchPath = ()) -> None:
        self.bindings.setdefault(name, []).append(Binding(lineno, is_sql, path))

    def holds_sql(self, name: str, lineno: int, path: BranchPath = ()) -> bool:
        """Does a binding that could reach this call hold SQL?

        Branches are merged conservatively: the last binding that definitely ran
        sets the base state, and any conditional binding since then can override
        it towards SQL. So `if x: q = "SELECT 1"` / `else: q = select(User)` is
        reported however the branches are ordered, while a plain reassignment in
        straight-line code is not.

        A name bound anywhere in this scope belongs to it, so lookup stops here
        rather than falling through to an enclosing scope that reuses the name.
        """
        if name not in self.bindings:
            # Enclosing scopes: a call's position within them is not knowable
            # here, so any SQL binding of the name counts.
            if self.parent is None:
                return False
            return any(b.is_sql for b in self.parent._all(name))

        reachable = [b for b in self.bindings[name] if b.lineno <= lineno and b.can_reach(path)]
        definite = [b for b in reachable if b.definitely_reaches(path)]
        base = definite[-1] if definite else None
        if base is not None and base.is_sql:
            return True
        floor = base.lineno if base is not None else 0
        return any(b.is_sql for b in reachable if b.lineno > floor and b is not base)

    def _all(self, name: str) -> list[Binding]:
        found = self.bindings.get(name, [])
        if found or self.parent is None:
            return found
        return self.parent._all(name)


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
        self.path: BranchPath = ()
        self.calls: list[tuple[ast.Call, Scope, BranchPath]] = []

    def _in_new_scope(self, node: ast.AST) -> None:
        outer, self.scope = self.scope, Scope(self.scope)
        outer_path, self.path = self.path, ()
        self.generic_visit(node)
        self.scope, self.path = outer, outer_path

    def _branch(self, node: ast.stmt, index: int, body: list[ast.stmt]) -> None:
        """Visit one arm of a conditional, recording that it may not run."""
        outer, self.path = self.path, (*self.path, (id(node), index))
        for statement in body:
            self.visit(statement)
        self.path = outer

    def visit_If(self, node: ast.If) -> None:
        self.visit(node.test)
        self._branch(node, 0, node.body)
        self._branch(node, 1, node.orelse)

    def visit_While(self, node: ast.While) -> None:
        self.visit(node.test)
        self._branch(node, 0, node.body)
        self._branch(node, 1, node.orelse)

    def visit_Try(self, node: ast.Try) -> None:
        self._branch(node, 0, node.body)
        for index, handler in enumerate(node.handlers, start=1):
            self._branch(node, index, handler.body)
        self._branch(node, len(node.handlers) + 1, node.orelse)
        for statement in node.finalbody:  # always runs
            self.visit(statement)

    def visit_TryStar(self, node: ast.TryStar) -> None:
        self.visit_Try(node)  # type: ignore[arg-type]

    def visit_Match(self, node: ast.Match) -> None:
        self.visit(node.subject)
        for index, case in enumerate(node.cases):
            self._branch(node, index, case.body)

    def visit_FunctionDef(self, node: ast.FunctionDef) -> None:
        self._visit_function(node)

    def visit_AsyncFunctionDef(self, node: ast.AsyncFunctionDef) -> None:
        self._visit_function(node)

    def _visit_function(self, node: ast.FunctionDef | ast.AsyncFunctionDef) -> None:
        outer, self.scope = self.scope, Scope(self.scope)
        args = node.args
        for arg in [*args.posonlyargs, *args.args, *args.kwonlyargs]:
            self.scope.bind(arg.arg, node.lineno, False, self.path)
        for maybe in (args.vararg, args.kwarg):
            if maybe is not None:
                self.scope.bind(maybe.arg, node.lineno, False, self.path)
        self.generic_visit(node)
        self.scope = outer

    def visit_Lambda(self, node: ast.Lambda) -> None:
        self._in_new_scope(node)

    def visit_ClassDef(self, node: ast.ClassDef) -> None:
        self._in_new_scope(node)

    def visit_Assign(self, node: ast.Assign) -> None:
        is_sql = carries_sql(node.value)
        for target in node.targets:
            for name in _bound_names(target):
                self.scope.bind(name, node.lineno, is_sql, self.path)
        self.generic_visit(node)

    def visit_AnnAssign(self, node: ast.AnnAssign) -> None:
        if node.value is not None:
            for name in _bound_names(node.target):
                self.scope.bind(name, node.lineno, carries_sql(node.value), self.path)
        self.generic_visit(node)

    def visit_AugAssign(self, node: ast.AugAssign) -> None:
        # An append keeps whatever the name already held, so `sql = "SELECT ..."`
        # followed by `sql += " WHERE ..."` stays SQL.
        appended = carries_sql(node.value)
        for name in _bound_names(node.target):
            already = self.scope.holds_sql(name, node.lineno)
            self.scope.bind(name, node.lineno, already or appended, self.path)
        self.generic_visit(node)

    def visit_NamedExpr(self, node: ast.NamedExpr) -> None:
        for name in _bound_names(node.target):
            self.scope.bind(name, node.lineno, carries_sql(node.value), self.path)
        self.generic_visit(node)

    def visit_For(self, node: ast.For) -> None:
        for name in _bound_names(node.target):
            self.scope.bind(name, node.lineno, False, self.path)
        self.visit(node.iter)
        self._branch(node, 0, node.body)  # the body may never run
        self._branch(node, 1, node.orelse)

    def visit_Call(self, node: ast.Call) -> None:
        self.calls.append((node, self.scope, self.path))
        self.generic_visit(node)


def _is_text_call(node: ast.expr | None) -> bool:
    """True for `text(...)`, `sa.text(...)`, `sqlalchemy.text(...)`."""
    if isinstance(node, ast.IfExp):
        return _is_text_call(node.body) or _is_text_call(node.orelse)
    if isinstance(node, ast.BoolOp):
        return any(_is_text_call(value) for value in node.values)
    if not isinstance(node, ast.Call):
        return False
    _, name = _callee(node.func)
    return name in SQL_TEXT_FUNCTIONS


def carries_sql(node: ast.expr | None) -> bool:
    """True if a value binds SQL, as a literal statement or a text() call."""
    return looks_like_sql(node) or _is_text_call(node)


def _is_sql_argument(node: ast.expr | None, scope: Scope, lineno: int, path: BranchPath) -> bool:
    if looks_like_sql(node):
        return True
    if isinstance(node, ast.Name) and scope.holds_sql(node.id, lineno, path):
        return True
    return _is_text_call(node)


def _describe(node: ast.Call, scope: Scope, path: BranchPath) -> str | None:
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
        if _is_sql_argument(first_arg, scope, node.lineno, path):
            return f"{label}() with a SQL string"
        return None

    if name in SQL_TEXT_FUNCTIONS:
        # The repository rule forbids hand-written SQL, not merely recognised
        # statements, and text() exists only to carry it.
        return f"{label}() - always raw SQL"

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


def _read_source(path: Path) -> str:
    """Never fail on encoding: a stray byte must not stop the whole scan."""
    try:
        return path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return path.read_text(encoding="utf-8", errors="replace")


def check_file(path: Path, display: str | None = None) -> list[str]:
    """Return one message per raw-SQL usage found in `path`.

    `display` is how the file is named in findings; it must be the same
    spelling exclude patterns match, or a path copied out of the output into
    an exclude entry will not match anything.
    """
    shown = display or str(path)
    source = _read_source(path)
    try:
        tree = ast.parse(source, filename=str(path))
    except SyntaxError as exc:
        return [f"{shown}:{exc.lineno or 0}: could not parse ({exc.msg})"]

    lines = source.splitlines()
    collector = _Collector()
    collector.visit(tree)
    parents = _parents(tree)
    reported: set[int] = set()
    hits: list[tuple[int, str]] = []

    # Outermost call first, so skipping calls nested inside a reported one keeps
    # `op.execute(text(...))` to a single message without collapsing unrelated
    # calls that merely share a line.
    def position(entry: tuple[ast.Call, Scope, BranchPath]) -> tuple[int, int]:
        return entry[0].lineno, entry[0].col_offset

    for node, scope, branch in sorted(collector.calls, key=position):
        if _enclosed_by(node, parents, reported):
            continue
        what = _describe(node, scope, branch)
        if what and not _allowed(node, lines):
            reported.add(id(node))
            hits.append((node.lineno, f"{shown}:{node.lineno}: {what}"))

    return [message for _, message in sorted(hits)]


class Result:
    """What the run found, and what it actually looked at.

    The counts exist so the invariant can be checked rather than assumed: a
    clean verdict is only meaningful if every file was examined. Three separate
    defects have produced "no raw SQL found" while examining nothing.
    """

    __slots__ = (
        "hits",
        "analysed",
        "excluded",
        "failed",
        "seen",
        "patterns",
        "applicable",
    )

    def __init__(self) -> None:
        self.hits: list[str] = []
        self.analysed = 0  # walked successfully
        self.excluded = 0  # skipped by an exclude pattern
        self.failed = 0  # could not be analysed; reported as a finding
        self.seen = 0
        self.patterns: dict[str, int] = {}
        self.applicable: set[str] = set()

    @property
    def unexamined(self) -> int:
        """Files in neither bucket.

        Zero by construction today; it is a reconciliation that must keep
        holding, so an edit adding an early exit to the loop is caught rather
        than quietly shrinking what gets checked.
        """
        return self.seen - self.analysed - self.excluded - self.failed

    @property
    def unused_patterns(self) -> list[str]:
        """Exclusions that matched nothing although their directory was scanned.

        A pattern for a directory this run did not look at is not stale: the
        pre-push hook scans only what changed, so erroring on those would make a
        valid config fail unrelated work.
        """
        return [
            pattern
            for pattern, count in self.patterns.items()
            if count == 0 and pattern in self.applicable
        ]


def check_paths(
    dirs: list[Path], excludes: list[str] | None = None, root: Path | None = None
) -> Result:
    """Check every file, reporting one that cannot be analysed rather than
    letting it abort the run and discard the violations already found."""
    patterns = excludes or []
    base = (root or Path.cwd()).resolve()
    result = Result()
    result.patterns = dict.fromkeys(patterns, 0)
    already: set[Path] = set()  # overlapping dirs must not count a file twice
    for directory in dirs:
        scanned = _relative(directory, base)
        for pattern in patterns:
            if _pattern_applies(pattern, scanned):
                result.applicable.add(pattern)
        for path in sorted(directory.rglob("*.py")):
            resolved = path.resolve()
            if resolved in already:
                continue
            already.add(resolved)
            result.seen += 1
            matched = _matching(path, patterns, base)
            if matched is not None:
                result.patterns[matched] += 1
                result.excluded += 1
                continue
            try:
                result.hits.extend(check_file(path, _relative(path, base)))
                result.analysed += 1
            except Exception as exc:  # noqa: BLE001 - one bad file must not end the run
                # Deliberately not waivable in-file: a marker that switches off
                # a whole file is a way to smuggle SQL past the check. Use an
                # exclude entry, which is visible in review.
                result.hits.append(
                    f"{_relative(path, base)}:0: could not be analysed "
                    f"({type(exc).__name__}); add it to "
                    f"[tool.check-no-raw-sql] exclude if that is expected"
                )
                result.failed += 1
    return result


def _pattern_applies(pattern: str, scanned: str) -> bool:
    """Could this pattern match anything under a directory this run scanned?

    Used only to decide whether a pattern matching nothing is stale. The
    pre-push hook scans just the directories that changed, so a pattern aimed
    elsewhere is not stale and must not fail the run.
    """
    if scanned in ("", "."):
        return True
    literal = re.split(r"[*?\[]", pattern, maxsplit=1)[0]
    directory = literal.rsplit("/", 1)[0] if "/" in literal else ""
    if not directory:
        # No directory part, so it is aimed repo-wide; only judge it on a full scan.
        return False
    return (
        directory == scanned
        or directory.startswith(f"{scanned}/")
        or scanned.startswith(f"{directory}/")
    )


def _relative(path: Path, root: Path) -> str:
    """Path as written in the repo, so patterns mean what they look like."""
    try:
        return path.resolve().relative_to(root).as_posix()
    except ValueError:
        return path.resolve().as_posix()


def _matching(path: Path, patterns: list[str], root: Path) -> str | None:
    """The pattern that excludes this file, or None.

    Matched against the repo-relative path only. Matching the bare filename as
    well meant `exclude = ["queries.py"]` quietly excluded every file of that
    name anywhere in the tree. `fnmatch` wildcards span `/`, so `*.generated.py`
    still reaches a nested file.
    """
    text = _relative(path, root)
    return next((pattern for pattern in patterns if fnmatch(text, pattern)), None)


def validate_pattern(pattern: str) -> str:
    """Reject a pattern that cannot match, instead of letting it do nothing.

    Patterns are repo-relative, so an absolute path or one climbing out of the
    tree never matches - and a silent no-op is how exclusions stop excluding.
    """
    if not pattern:
        raise ValueError("exclude pattern is empty")
    posix = PurePosixPath(pattern)
    windows = PureWindowsPath(pattern)
    if posix.is_absolute() or windows.is_absolute():
        raise ValueError(f"exclude pattern must be repo-relative, not absolute: {pattern!r}")
    if ".." in posix.parts or ".." in windows.parts:
        raise ValueError(f"exclude pattern must stay inside the repo: {pattern!r}")
    return pattern


def load_excludes(config: Path) -> list[str]:
    """Exclusions live in pyproject.toml so they are visible in review."""
    if not config.is_file():
        return []
    with config.open("rb") as handle:
        data = tomllib.load(handle)
    section = data.get("tool", {}).get("check-no-raw-sql", {})
    patterns = section.get("exclude", [])
    if not isinstance(patterns, list) or any(not isinstance(p, str) for p in patterns):
        raise ValueError("[tool.check-no-raw-sql] exclude must be a list of strings")
    return [validate_pattern(pattern) for pattern in patterns]


def _parse_args(argv: list[str]) -> tuple[list[Path], list[str]]:
    """Strict: an argument that is not an existing directory is an error.

    Silently dropping a mistyped path is how a check comes back clean without
    having looked at anything.
    """
    paths: list[Path] = []
    excludes: list[str] = []
    rest = list(argv)
    while rest:
        arg = rest.pop(0)
        if arg == "--exclude":
            if not rest:
                raise ValueError("--exclude needs a pattern")
            excludes.append(validate_pattern(rest.pop(0)))
        elif arg.startswith("--exclude="):
            excludes.append(validate_pattern(arg.split("=", 1)[1]))
        elif arg.startswith("-"):
            raise ValueError(f"unknown option: {arg}")
        else:
            candidate = Path(arg)
            if not candidate.is_dir():
                raise ValueError(f"not a directory: {arg}")
            paths.append(candidate)
    return paths, excludes


def main(argv: list[str]) -> int:
    try:
        dirs, excludes = _parse_args(argv)
        excludes += load_excludes(Path("pyproject.toml"))
    except (ValueError, tomllib.TOMLDecodeError) as exc:
        print(f"check-no-raw-sql: {exc}", file=sys.stderr)
        return 2

    if not dirs:
        print("no directories to check, skipping")
        return 0

    result = check_paths(dirs, excludes)

    if result.unused_patterns:
        for pattern in result.unused_patterns:
            print(
                f"check-no-raw-sql: exclude pattern matched no file: {pattern!r} "
                "(patterns are matched against the repo-relative path)",
                file=sys.stderr,
            )
        return 2

    # The invariant: a clean verdict means every file was examined. If this ever
    # fails, the check has stopped checking - say so rather than report success.
    if result.unexamined:
        print(
            f"check-no-raw-sql: {result.unexamined} file(s) were neither analysed "
            "nor excluded; refusing to report a result",
            file=sys.stderr,
        )
        return 2

    if result.hits:
        print("Hand-written SQL found (forbidden - use the ORM instead):", file=sys.stderr)
        for hit in result.hits:
            print(f"  {hit}", file=sys.stderr)
        print(f"If a line is a false positive, mark it with `# {ALLOW_MARKER}`.", file=sys.stderr)
        return 1

    excluded = f", {result.excluded} excluded" if result.excluded else ""
    print(f"no raw SQL found ({result.analysed} file(s) checked{excluded})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
