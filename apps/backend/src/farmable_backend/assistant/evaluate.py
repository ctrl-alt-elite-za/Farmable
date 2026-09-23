"""Run deterministic development protocol/security evaluations, never paid calls."""

import argparse
import subprocess
import sys
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--set", choices=["dev"], required=True)
    parser.parse_args()
    root = Path(__file__).resolve().parents[5]
    print("Synthetic protocol/security checks only; not a live-model quality or judge report.")
    return subprocess.run(  # noqa: S603 -- fixed interpreter, tests and arguments.
        [sys.executable, "-m", "pytest", "apps/backend/tests/test_assistant.py", "-q"],
        cwd=root,
        check=False,
    ).returncode


if __name__ == "__main__":
    raise SystemExit(main())
