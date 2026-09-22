"""Keep the real PostgreSQL suite in the existing required integration job."""

import json
import shlex
from pathlib import Path

import yaml


def test_photo_sync_runs_explicitly_before_database_shutdown():
    root = Path(__file__).resolve().parents[2]
    lines = (root / "scripts/test-integration.sh").read_text().splitlines()
    suite = "apps/backend/tests/integration/test_photo_sync_postgres.py"
    selected = [(index, shlex.split(line)) for index, line in enumerate(lines) if suite in line]
    assert len(selected) == 1
    index, command = selected[0]
    assert command[:6] == ["${compose[@]}", "run", "--rm", "tests", "pytest", suite]
    assert command[6:] == ["-m", "integration", "-q"]
    assert index < next(i for i, line in enumerate(lines) if '"${compose[@]}" stop worker' in line)
    assert "integration-tests" in json.loads((root / ".github/required-checks.json").read_text())
    workflow = yaml.safe_load((root / ".github/workflows/pr-checks.yml").read_text())
    matrix = workflow["jobs"]["checks"]["strategy"]["matrix"]["include"]
    assert {"check": "integration-tests", "backend": True} in matrix
