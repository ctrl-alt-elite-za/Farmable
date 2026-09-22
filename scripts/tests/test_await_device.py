"""Drive scripts/await-device.sh against stub adb binaries.

These are behavioural rather than textual on purpose. The first version of the
helper compared adb's output without stripping the carriage return adb
actually sends, so the comparison never matched and the helper would have
failed on every run — turning a fix for a flake into a permanent failure.
Reading the script did not catch that. Running it does.
"""

import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "scripts" / "await-device.sh"


def _posix_bash() -> str | None:
    """Find a POSIX bash, not Windows' WSL launcher.

    shutil.which("bash") finds System32's bash.exe first on a machine with WSL
    enabled. That is a launcher for a Linux VM, not a shell that can see this
    checkout, and it fails with an opaque HCS mount error that looks nothing
    like the PATH problem it resembles.
    """
    found = shutil.which("bash")
    if found and "system32" not in found.replace("\\", "/").lower():
        return found
    for candidate in (
        "C:/Program Files/Git/bin/bash.exe",
        "C:/Program Files/Git/usr/bin/bash.exe",
    ):
        if Path(candidate).exists():
            return candidate
    return None


BASH = _posix_bash()

pytestmark = pytest.mark.skipif(BASH is None, reason="needs a POSIX bash")


def _bash_path(path: Path) -> str:
    """Render a path the way bash expects it.

    The interpreter is always bash, even on Windows, so a drive-letter path
    has to become POSIX. Getting this wrong makes the stub invisible and every
    case silently falls through to the real adb.
    """
    text = Path(path).as_posix()
    if len(text) > 1 and text[1] == ":":
        return "/" + text[0].lower() + text[2:]
    return text


def run(tmp_path: Path, script: str, *, timeout_seconds: str = "6") -> subprocess.CompletedProcess:
    """Put a stub adb first on PATH and run the helper against it."""
    stub = tmp_path / "adb"
    stub.write_text("#!/usr/bin/env bash\n" + script, encoding="utf-8")
    stub.chmod(0o755)

    # Let bash build its own POSIX PATH with -l, then prepend the stub. Handing
    # bash Python's Windows-style PATH makes `timeout` resolve to Windows'
    # timeout.exe, an unrelated program, and every case then breaks in a way
    # that looks like the helper is at fault.
    env = {
        **os.environ,
        "AWAIT_DEVICE_TIMEOUT": timeout_seconds,
        "AWAIT_DEVICE_PROBE_TIMEOUT": "2",
    }
    command = 'PATH="' + _bash_path(tmp_path) + ':$PATH" exec bash "' + _bash_path(HELPER) + '"'
    return subprocess.run(  # noqa: S603 - fixed interpreter and script path
        [BASH, "-lc", command],
        cwd=ROOT,
        env=env,
        capture_output=True,
        text=True,
        timeout=60,
    )


def test_a_booted_device_succeeds(tmp_path: Path) -> None:
    result = run(tmp_path, 'if [ "$1" = "shell" ]; then printf "1\\r\\n"; fi\nexit 0\n')
    assert result.returncode == 0, result.stdout + result.stderr


def test_the_carriage_return_adb_sends_is_stripped() -> None:
    """Android's shell terminates lines with CRLF; the CR has to go.

    This is asserted textually rather than behaviourally, and that is a real
    limitation worth stating. A bash stub cannot reproduce it on Windows:
    MSYS normalises the stub's output, so `printf "1\\r\\n"` reaches the helper
    as plain "1\\n" and a behavioural test passes whether or not the strip is
    present. Verified with od.

    On Linux CI the stub would carry the CR, so this could be behavioural
    there — but a test that only bites on one platform is a trap for whoever
    next runs the suite locally and sees green.

    The regression this guards is not hypothetical: the first version of the
    helper shipped deleting the empty set instead of the CR, which would have
    failed every run.
    """
    probe = next(
        line
        for line in HELPER.read_text(encoding="utf-8").splitlines()
        if line.strip().startswith("booted=")
    )
    # Assert on the line that runs, not the file. Checking the whole file
    # passes on the explanatory comment above it, which is how the first
    # version of this assertion managed to stay green with the bug present.
    assert "tr -d '\\r'" in probe, "the CR strip is gone; adb returns '1\\r'"
    assert "\r" not in probe, "a literal CR byte in source; use the escape"


def test_a_device_that_never_boots_fails_within_the_deadline(tmp_path: Path) -> None:
    result = run(tmp_path, 'if [ "$1" = "shell" ]; then printf "0\\r\\n"; fi\nexit 0\n')
    assert result.returncode == 1
    assert "did not answer adb" in result.stderr


def test_a_hanging_wait_for_device_still_fails(tmp_path: Path) -> None:
    """adb wait-for-device blocks forever by default.

    A deadline around the polling loop alone never fires here, because control
    never reaches the loop. This is the finding from the review of PR #55.
    """
    started = time.monotonic()
    result = run(tmp_path, "sleep 300\n", timeout_seconds="4")
    elapsed = time.monotonic() - started

    assert result.returncode == 1
    assert elapsed < 30, f"helper was not bounded; took {elapsed:.1f}s"


def test_a_hanging_probe_still_fails(tmp_path: Path) -> None:
    """adb shell can hang on a half-dead connection rather than erroring."""
    started = time.monotonic()
    result = run(
        tmp_path,
        'if [ "$1" = "shell" ]; then sleep 300; fi\nexit 0\n',
        timeout_seconds="5",
    )
    elapsed = time.monotonic() - started

    assert result.returncode == 1
    assert elapsed < 30, f"a probe outlived the budget; took {elapsed:.1f}s"


def test_a_device_that_boots_late_is_still_accepted(tmp_path: Path) -> None:
    """Recovery is the point: a device that comes back must be picked up."""
    marker = _bash_path(tmp_path / "attempts")
    script = (
        'if [ "$1" = "shell" ]; then\n'
        '  n=$(cat "' + marker + '" 2>/dev/null || echo 0)\n'
        '  n=$((n + 1)); echo "$n" > "' + marker + '"\n'
        '  if [ "$n" -ge 2 ]; then printf "1\\r\\n"; else printf "\\r\\n"; fi\n'
        "fi\n"
        "exit 0\n"
    )
    # Generous on purpose. This asserts that a returning device is picked up,
    # not that it happens quickly — and each probe spawns a login shell, which
    # on Windows is slow enough to eat a tight budget when the whole file runs.
    # The boundedness tests above are where the deadline is actually proved.
    result = run(tmp_path, script, timeout_seconds="20")
    assert result.returncode == 0, result.stdout + result.stderr


def test_the_stack_waits_after_stopping_the_api() -> None:
    """Ordering still matters: the wait must follow the stop.

    Anywhere else it proves nothing about the moment the connection is lost.
    """
    stack = (ROOT / "scripts" / "ci-stack.sh").read_text(encoding="utf-8")
    stop = stack.index('"${compose[@]}" stop api')
    offline = stack.index("maestro test e2e/mobile/offline_launch.yaml")
    recovery = stack.rindex("bash scripts/await-device.sh")
    assert stop < recovery < offline


if __name__ == "__main__":
    sys.exit(pytest.main([__file__]))
