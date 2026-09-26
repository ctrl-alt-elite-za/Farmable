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


@pytest.mark.parametrize("scan_fails", [False, True])
def test_mobile_runner_executes_scan_and_propagates_failure(
    tmp_path: Path, scan_fails: bool
) -> None:
    bash = os.environ.get("FARMABLE_TEST_BASH") or shutil.which("bash")
    if bash is None:
        pytest.skip("Bash is required")
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    for name in ("ci-stack.sh", "await-device.sh"):
        shutil.copyfile(REPO / "scripts" / name, scripts / name)
    log = tmp_path / "calls.log"
    result = subprocess.run(  # noqa: S603
        [
            bash,
            "-c",
            """
docker() { printf 'docker %s\n' "$*" >> "$TASK_LOG"; }
uv() {
  case "$*" in
    *token_hex*) printf 'fake-password\n' ;;
    *URL.create*) printf 'postgresql+psycopg://test:fake-password@database/test\n' ;;
    *uuid*) printf 'mobile-test-id\n' ;;
  esac
}
git() { printf 'test-sha\n'; }
adb() {
  printf 'adb %s\n' "$*" >> "$TASK_LOG"
  if [ "$*" = 'shell getprop sys.boot_completed' ]; then printf '1\n'; fi
  return 0
}
timeout() { shift; "$@"; }
maestro() {
  printf 'maestro %s\n' "$*" >> "$TASK_LOG"
  if [ "$*" = 'test e2e/mobile/scan_pan.yaml' ] && [ "$TASK_SCAN_FAILS" = true ]; then
    return 23
  fi
  return 0
}
export -f docker uv git adb timeout maestro
bash "$1" mobile
""",
            "test",
            (scripts / "ci-stack.sh").as_posix(),
        ],
        env={
            **os.environ,
            "TASK_LOG": log.as_posix(),
            "TASK_SCAN_FAILS": str(scan_fails).lower(),
            "APK": "test-mode.apk",
            "GITHUB_ACTIONS": "false",
        },
        capture_output=True,
        text=True,
        timeout=30,
        check=False,
    )
    calls = log.read_text(encoding="utf-8").splitlines()
    flows = [call for call in calls if call.startswith("maestro ")]
    expected = ["online_launch", "signup", "login", "scan_pan"]
    if not scan_fails:
        expected += [
            "upload_offline_resume",
            "first_launch_setup",
            "dashboard_degraded",
            "dashboard_offline",
            "offline_launch",
        ]
    assert flows == [f"maestro test e2e/mobile/{name}.yaml" for name in expected]
    assert result.returncode == (23 if scan_fails else 0), result.stdout + result.stderr
    scan = calls.index("maestro test e2e/mobile/scan_pan.yaml")
    assert calls[scan - 1] == "adb shell getprop sys.boot_completed"
    # The first-launch journey (#89) gets its own device check too. It runs
    # after the scan, so a failed scan stops the run before it.
    if not scan_fails:
        first_launch = calls.index("maestro test e2e/mobile/first_launch_setup.yaml")
        assert calls[first_launch - 1] == "adb shell getprop sys.boot_completed"
    assert calls[-1].endswith("down --volumes --remove-orphans")
    assert any(call.endswith("stop api") for call in calls) is not scan_fails
