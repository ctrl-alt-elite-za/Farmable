"""Keep account PostgreSQL coverage in the required integration job."""

import shlex
from pathlib import Path


def test_account_postgres_suites_are_explicitly_selected():
    root = Path(__file__).resolve().parents[2]
    lines = (root / "scripts/test-integration.sh").read_text().splitlines()
    selected = [
        shlex.split(line)
        for line in lines
        if "test_account_postgres.py" in line or "test_backfill_account_farms_postgres.py" in line
    ]

    assert len(selected) == 1
    command = selected[0]
    assert command[:7] == [
        "${compose[@]}",
        "run",
        "--rm",
        "tests",
        "pytest",
        "-o",
        "addopts=",
    ]
    assert command[7:] == [
        "apps/backend/tests/integration/test_account_postgres.py",
        "apps/backend/tests/integration/test_backfill_account_farms_postgres.py",
        "-m",
        "integration",
        "-q",
    ]
