"""Check that the registered backtest protocol precedes result artifacts.

The check deliberately reads the first-parent history of a named mainline ref.
That makes a normal merge and a squash merge equivalent: the commit whose tree
first contains the path is the mainline introduction.  Commit timestamps and
the current branch's ancestry are not used as ordering evidence.

``--check-ready`` is the preparation check used before results exist.  It
requires the working ``PROTOCOL.md`` to byte-match the protocol at the mainline
tip, but it does not require a result.  The default check additionally requires
the current mainline tip to contain a tracked result file and requires the
first result introduction to be strictly later than the first protocol
introduction.

Every tracked file below ``ml/backtest/results/`` counts as a result artifact,
including ``.gitkeep``.  Counting all tracked names keeps a placeholder from
silently changing the ordering contract; callers that want an empty results
directory should leave it untracked.
"""

from __future__ import annotations

import argparse
import dataclasses
import shutil
import subprocess
import sys
from collections.abc import Sequence
from pathlib import Path

PROTOCOL_PATH = "ml/backtest/PROTOCOL.md"
RESULTS_PATH = "ml/backtest/results"
AMENDMENT_TWO_MARKER = (
    b"### Amendment 2 \xe2\x80\x94 25 September 2026: seven-default decision evaluation"
)


class ProtocolGateError(RuntimeError):
    """A repository cannot provide reliable protocol-order evidence."""


@dataclasses.dataclass(frozen=True)
class GateResult:
    """Evidence returned by :func:`check_protocol_first`."""

    protocol_commit: str
    results_commit: str | None
    check_ready: bool

    @property
    def ready(self) -> bool:
        return self.results_commit is not None or self.check_ready


def _run_git_bytes(repo: Path, *args: str, check: bool = True) -> bytes:
    """Run git without a shell and return stdout bytes."""

    git = shutil.which("git")
    if git is None:
        raise ProtocolGateError("git executable is not available on PATH")
    completed = subprocess.run(  # noqa: S603 - fixed git executable and argument list
        [git, *args],
        cwd=repo,
        check=False,
        capture_output=True,
        text=False,
    )
    if completed.returncode and check:
        stderr = completed.stderr.decode("utf-8", errors="replace").strip()
        detail = f": {stderr}" if stderr else ""
        raise ProtocolGateError(
            f"git {' '.join(args)} failed with exit {completed.returncode}{detail}"
        )
    return completed.stdout


def _run_git(repo: Path, *args: str, check: bool = True) -> str:
    """Run git without a shell and return decoded stdout."""

    return _run_git_bytes(repo, *args, check=check).decode("utf-8", errors="replace")


def _main_commit(repo: Path, main_ref: str) -> str:
    try:
        return _run_git(repo, "rev-parse", "--verify", f"{main_ref}^{{commit}}").strip()
    except ProtocolGateError as exc:
        raise ProtocolGateError(
            f"mainline history is unavailable: ref {main_ref!r} does not resolve to a commit"
        ) from exc


def _require_complete_history(repo: Path) -> None:
    shallow = _run_git(repo, "rev-parse", "--is-shallow-repository").strip().lower()
    if shallow == "true":
        raise ProtocolGateError(
            "mainline history is shallow; fetch the complete history before running the gate"
        )


def _tracked_at(repo: Path, commit: str, path: str) -> bool:
    result = _run_git(repo, "ls-tree", "-r", "--name-only", commit, "--", path)
    names = {line.strip() for line in result.splitlines() if line.strip()}
    if path == RESULTS_PATH:
        prefix = f"{RESULTS_PATH}/"
        return any(name.startswith(prefix) for name in names)
    return path in names


def _working_protocol(repo: Path) -> bytes:
    path = repo / Path(PROTOCOL_PATH)
    try:
        return path.read_bytes()
    except FileNotFoundError as exc:
        raise ProtocolGateError(f"working protocol is missing: {PROTOCOL_PATH}") from exc
    except OSError as exc:
        raise ProtocolGateError(f"cannot read working protocol {PROTOCOL_PATH}: {exc}") from exc


def _first_parent_commits(repo: Path, commit: str) -> list[str]:
    commits = [
        line.strip()
        for line in _run_git(repo, "rev-list", "--first-parent", "--reverse", commit).splitlines()
    ]
    if not commits:
        raise ProtocolGateError("mainline history contains no commits")
    return commits


def _mainline_introduction(repo: Path, commits: Sequence[str], path: str) -> str | None:
    """Return the first first-parent commit whose tree contains ``path``.

    Looking at each first-parent tree handles merge commits consistently even
    when Git's merge diff/path simplification would omit a file introduced by
    the merged side branch.  The first containing tree is retained if the
    artifact is later deleted and re-added, so it cannot evade the gate.
    """

    for candidate in commits:
        if _tracked_at(repo, candidate, path):
            return candidate
    return None


def check_protocol_first(
    *,
    repo: str | Path | None = None,
    main_ref: str = "origin/main",
    check_ready: bool = False,
) -> GateResult:
    """Validate protocol content and mainline ordering.

    Raises :class:`ProtocolGateError` for every failed gate.  ``repo`` may be
    a temporary repository path, which keeps the checker usable in offline
    tests and in the credential-free Colab workflow.
    """

    repository = Path(repo) if repo is not None else Path.cwd()
    repository = repository.resolve()
    if not repository.is_dir():
        raise ProtocolGateError(f"repository does not exist or is not a directory: {repository}")

    _require_complete_history(repository)
    main_commit = _main_commit(repository, main_ref)
    if not _tracked_at(repository, main_commit, PROTOCOL_PATH):
        raise ProtocolGateError(f"protocol is missing from mainline {main_ref}: {PROTOCOL_PATH}")

    expected = _run_git_bytes(repository, "show", f"{main_commit}:{PROTOCOL_PATH}")
    if _working_protocol(repository) != expected:
        raise ProtocolGateError(
            f"working protocol does not exactly match merged {main_ref}:{PROTOCOL_PATH}; "
            "the protocol has an unmerged change"
        )

    first_parent_commits = _first_parent_commits(repository, main_commit)
    protocol_commit = _mainline_introduction(repository, first_parent_commits, PROTOCOL_PATH)
    if protocol_commit is None:
        raise ProtocolGateError("could not identify the protocol's first mainline introduction")

    results_commit = _mainline_introduction(repository, first_parent_commits, RESULTS_PATH)
    results_at_tip = _tracked_at(repository, main_commit, RESULTS_PATH)

    if results_commit is not None:
        positions = {item.strip(): index for index, item in enumerate(first_parent_commits)}
        protocol_position = positions.get(protocol_commit)
        results_position = positions.get(results_commit)
        if protocol_position is None or results_position is None:
            raise ProtocolGateError(
                "protocol/result introduction is outside the complete mainline history"
            )
        if results_position <= protocol_position:
            raise ProtocolGateError(
                "backtest results were introduced before or in the same mainline "
                "commit as the protocol"
            )

    if not results_at_tip:
        if check_ready:
            return GateResult(protocol_commit, None, True)
        raise ProtocolGateError(
            "no tracked backtest result artifact exists on mainline; "
            "use --check-ready while preparing the protocol"
        )

    return GateResult(protocol_commit, results_commit, check_ready)


def check_amendment_two_merged(
    *, repo: str | Path | None = None, main_ref: str = "origin/main"
) -> str:
    """Return the first mainline commit containing the exact merged amendment."""
    repository = (Path(repo) if repo is not None else Path.cwd()).resolve()
    check_protocol_first(repo=repository, main_ref=main_ref, check_ready=True)
    commits = _first_parent_commits(repository, _main_commit(repository, main_ref))
    amendment_commit = next(
        (
            commit
            for commit in commits
            if _tracked_at(repository, commit, PROTOCOL_PATH)
            and AMENDMENT_TWO_MARKER
            in _run_git_bytes(repository, "show", f"{commit}:{PROTOCOL_PATH}")
        ),
        None,
    )
    if amendment_commit is None:
        raise ProtocolGateError("seven-default amendment is not independently merged on mainline")
    return amendment_commit


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Verify that the merged backtest protocol precedes mainline results."
    )
    parser.add_argument(
        "--check-ready",
        action="store_true",
        help="allow preparation before any tracked result artifact exists",
    )
    parser.add_argument(
        "--main-ref",
        default="origin/main",
        help="mainline ref to inspect (default: origin/main)",
    )
    parser.add_argument(
        "--repo",
        type=Path,
        help="repository to inspect (default: current directory)",
    )
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        evidence = check_protocol_first(
            repo=args.repo,
            main_ref=args.main_ref,
            check_ready=args.check_ready,
        )
    except ProtocolGateError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 1

    if evidence.results_commit is None:
        print(
            "READY: merged protocol matches the working content; no results exist yet "
            f"(protocol {evidence.protocol_commit[:12]})."
        )
    else:
        print(
            "PASS: protocol precedes results on mainline "
            f"(protocol {evidence.protocol_commit[:12]}, results {evidence.results_commit[:12]})."
        )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
