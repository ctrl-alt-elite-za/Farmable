"""Temporary-repository tests for the protocol history gate."""

from __future__ import annotations

import shutil
import subprocess
import sys
from pathlib import Path

import pytest

CHECKER = Path(__file__).with_name("check_protocol_first.py")


def _git(repo: Path, *args: str) -> str:
    git = shutil.which("git")
    assert git is not None
    completed = subprocess.run(  # noqa: S603 - test fixture controls the fixed git arguments
        [git, *args],
        cwd=repo,
        check=True,
        capture_output=True,
        text=True,
    )
    return completed.stdout


def _commit(repo: Path, message: str) -> str:
    _git(repo, "add", "--all")
    _git(repo, "commit", "-m", message)
    return _git(repo, "rev-parse", "HEAD").strip()


def _repo(tmp_path: Path) -> Path:
    repo = tmp_path / "repo"
    repo.mkdir()
    _git(repo, "init", "--initial-branch=main")
    _git(repo, "config", "user.email", "test@example.invalid")
    _git(repo, "config", "user.name", "Protocol Test")
    _git(repo, "config", "core.autocrlf", "false")
    (repo / "README").write_bytes(b"base\n")
    _commit(repo, "base")
    return repo


def _run(repo: Path, *args: str) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603 - test fixture controls the fixed git arguments
        [sys.executable, str(CHECKER), "--repo", str(repo), "--main-ref", "main", *args],
        cwd=repo,
        capture_output=True,
        text=True,
    )


def _add_protocol(repo: Path, text: str = "version 1\n") -> str:
    path = repo / "ml" / "backtest" / "PROTOCOL.md"
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(text.encode("utf-8"))
    return _commit(repo, "merge protocol")


def _add_result(repo: Path, name: str = "decision_backtest.json") -> str:
    path = repo / "ml" / "backtest" / "results" / "run-1" / name
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(b"{}\n")
    return _commit(repo, "publish result")


def test_check_ready_accepts_merged_protocol_without_results(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    protocol = _add_protocol(repo)

    result = _run(repo, "--check-ready")

    assert result.returncode == 0, result.stderr
    assert "READY" in result.stdout
    assert protocol[:12] in result.stdout

    final = _run(repo)
    assert final.returncode != 0
    assert "no tracked backtest result" in final.stderr


def test_default_accepts_protocol_then_result_on_first_parent(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    protocol = _add_protocol(repo)
    result_commit = _add_result(repo)

    result = _run(repo)

    assert result.returncode == 0, result.stderr
    assert "PASS" in result.stdout
    assert protocol[:12] in result.stdout
    assert result_commit[:12] in result.stdout


def test_accepts_a_protocol_added_by_a_merge_commit(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    _git(repo, "checkout", "-b", "protocol-pr")
    _add_protocol(repo)
    _git(repo, "checkout", "main")
    _git(repo, "merge", "--no-ff", "protocol-pr", "-m", "merge protocol PR")
    _add_result(repo)

    result = _run(repo)

    assert result.returncode == 0, result.stderr


def test_accepts_a_squashed_protocol_pr(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    _git(repo, "checkout", "-b", "protocol-pr")
    _add_protocol(repo)
    _git(repo, "checkout", "main")
    _git(repo, "merge", "--squash", "protocol-pr")
    _commit(repo, "squashed protocol PR")
    _add_result(repo)

    result = _run(repo)

    assert result.returncode == 0, result.stderr


@pytest.mark.parametrize("layout", ["same", "results-first"])
def test_rejects_results_not_strictly_after_protocol(tmp_path: Path, layout: str) -> None:
    repo = _repo(tmp_path)
    if layout == "same":
        _add_protocol(repo)
        _add_result(repo)
        # Collapse the two ordinary commits into one mainline introduction.
        _git(repo, "reset", "--soft", "HEAD~2")
        _commit(repo, "protocol and result together")
    else:
        _add_result(repo)
        _add_protocol(repo)

    result = _run(repo)

    assert result.returncode != 0
    assert "before or in the same" in result.stderr


def test_rejects_unmerged_protocol_content(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    _add_protocol(repo, "version 1\n")
    (repo / "ml" / "backtest" / "PROTOCOL.md").write_bytes(b"version 2\n")

    result = _run(repo, "--check-ready")

    assert result.returncode != 0
    assert "unmerged change" in result.stderr


def test_deleted_and_readded_result_still_uses_first_introduction(tmp_path: Path) -> None:
    repo = _repo(tmp_path)
    _add_protocol(repo)
    first_result = _add_result(repo)
    result_dir = repo / "ml" / "backtest" / "results"
    for child in result_dir.rglob("*"):
        if child.is_file():
            child.unlink()
    _commit(repo, "remove result")
    second_result = _add_result(repo, "decision_backtest.md")

    result = _run(repo)

    assert result.returncode == 0, result.stderr
    assert first_result[:12] in result.stdout
    assert second_result[:12] not in result.stdout


def test_rejects_shallow_history(tmp_path: Path) -> None:
    source = _repo(tmp_path)
    _add_protocol(source)
    _add_result(source)
    clone = tmp_path / "clone"
    git = shutil.which("git")
    assert git is not None
    subprocess.run(  # noqa: S603 - test fixture controls the fixed git arguments
        [git, "clone", "--depth", "1", "--no-local", str(source), str(clone)],
        check=True,
        capture_output=True,
        text=True,
    )

    result = _run(clone)

    assert result.returncode != 0
    assert "shallow" in result.stderr
