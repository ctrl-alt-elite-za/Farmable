"""Verify isolation and cleanup behavior without needing Docker."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("failure", ["none", "tests", "build", "credentials", "engine"])
@pytest.mark.parametrize(
    "runner,project,argument",
    [
        ("scripts/test-integration.sh", "farmable-test", ""),
        ("scripts/ci-stack.sh", "farmable-ci", "e2e-degradation"),
    ],
)
def test_integration_runner_isolated_cleanup(
    tmp_path: Path, failure: str, runner: str, project: str, argument: str
) -> None:
    bash = os.environ.get("FARMABLE_TEST_BASH") or shutil.which("bash")
    if bash is None:
        pytest.skip("Bash is required")
    log = tmp_path / "calls.log"
    result = subprocess.run(  # noqa: S603
        [
            bash,
            "-c",
            """
docker() {
  if [ "$1" = info ]; then
    [ "$TASK_FAILURE" != engine ]; return $?
  fi
  printf '%s\n' "$*" >> "$TASK_LOG"
  case "$*" in
    *' build'*) [ "$TASK_FAILURE" != build ]; return $? ;;
    *' run '*tests*) [ "$TASK_FAILURE" != tests ]; return $? ;;
  esac
  return 0
}
uv() {
  case "$*" in
    *token_hex*) [ "$TASK_FAILURE" != credentials ] || return 17; printf 'fake-password\n' ;;
    *URL.create*) printf 'postgresql+psycopg://test:fake-password@database/test\n' ;;
    *uuid*) printf 'unique-test-id\n' ;;
  esac
}
git() { printf 'test-sha\n'; }
export -f docker uv git
bash "$1" "$2"
""",
            "test",
            (REPO / runner).as_posix(),
            argument,
        ],
        env={
            **os.environ,
            "TASK_FAILURE": failure,
            "TASK_LOG": log.as_posix(),
            "GITHUB_ACTIONS": "false",
        },
        capture_output=True,
        text=True,
        check=False,
    )
    calls = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
    assert result.returncode == (0 if failure == "none" else 1 if failure != "credentials" else 17)
    assert "fake-password" not in result.stdout + result.stderr
    if failure in {"engine", "credentials"}:
        assert calls == []
    else:
        assert calls[-1].endswith("down --volumes --remove-orphans")
        assert all(f"-p {project}-unique-test-id -f compose.yaml" in call for call in calls)
    if failure == "none":
        assert any("stop worker" in call for call in calls)
        assert any("stop database" in call for call in calls)
        assert any("--no-deps tests" in call for call in calls)
