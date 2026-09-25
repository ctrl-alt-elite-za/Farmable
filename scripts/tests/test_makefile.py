"""Makefile dependency guards."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest


def test_make_test_skips_node_when_node_is_absent(tmp_path: Path):
    make = shutil.which("make")
    bash = shutil.which("bash")
    if make is None or bash is None:
        pytest.skip("make/bash are unavailable")

    # Stub the later tool invocations so this test isolates the Node guard.
    bin_dir = tmp_path / "bin"
    bin_dir.mkdir()
    for name in ("uv", "pnpm"):
        shim = bin_dir / name
        shim.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
        shim.chmod(0o755)
    # Keep only the stubs: make is invoked by absolute path and the recipe's
    # shell is absolute, so this guarantees that node cannot be discovered.
    env = {**os.environ, "PATH": str(bin_dir)}
    result = subprocess.run(
        [make, "test"],
        cwd=Path(__file__).parents[2],
        env=env,
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr
    assert "node not found; skipping Turnstile page tests" in result.stdout
