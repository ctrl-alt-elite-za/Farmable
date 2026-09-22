"""Run one fixed check once. Artifacts contain enums/counts, NEVER arbitrary log excerpts."""

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

from ci_checks import CHECKS, DIAGNOSTICS


def diagnostics(output: str) -> list[str]:
    rules = {
        "type-error": r"(?:error TS\d+|error:.*\[[a-z-]+\])",
        "lint-error": r"(?:\b[EFSIB]\d{3}\b|eslint.*error)",
        "test-failed": r"(?:\bFAILED\b|\d+ failed)",
        "drop-column": r"\bDROP\s+COLUMN\b|ban-drop-column",
        "drop-table": r"\bDROP\s+TABLE\b|ban-drop-table",
        "migration-danger": r"migration-danger",
        "audit-high": r"audit-high",
        "audit-unknown": r"audit-unknown",
        "client-stale": r"client-stale",
        "prerequisite": r"prerequisite",
    }
    return [name for name, pattern in rules.items() if re.search(pattern, output, re.I)]


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("check", choices=CHECKS)
    args = parser.parse_args()
    # Local reproduction strings are never evaluated as a shell command.
    targets = {
        "unit-tests": "test",
        "integration-tests": "test-integration",
        "client-up-to-date": "client-check",
        "no-raw-sql": "check-no-raw-sql",
        "mobile-test": "mobile-checks",
    }
    target = targets.get(args.check, args.check)
    reports = Path(".ci-reports")
    reports.mkdir(exist_ok=True)
    codes: list[str] = []
    make = shutil.which("make")
    if make is None:
        raise RuntimeError("GNU Make is required")
    try:
        completed = subprocess.run(  # noqa: S603
            [make, target],
            capture_output=True,
            text=True,
            timeout=25 * 60,
            check=False,
        )
        output = completed.stdout + completed.stderr
        print(output, end="")  # Logs stay in the read-only job, not privileged comments/artifacts.
        exit_code = completed.returncode
        codes = diagnostics(output)
        quarantined = sorted({int(n) for n in re.findall(r"quarantined: #(\d+)", output)})
    except subprocess.TimeoutExpired:
        exit_code, codes, quarantined = 1, ["timeout"], []
    result = {
        "check": args.check,
        "failed": exit_code != 0,
        "diagnostics": codes,
        "quarantined": quarantined,
    }
    (reports / (args.check + ".json")).write_text(json.dumps(result), encoding="utf-8")
    summary = f"### {args.check}: {'failed' if exit_code else 'passed'}\n\n"
    summary += f"Reproduce: `{CHECKS[args.check][0]}`\n\n{CHECKS[args.check][1]}\n"
    summary += "".join(f"\n- {DIAGNOSTICS[code]}" for code in codes)
    summary += "".join(f"\n- Warning: quarantined test linked to #{n}." for n in quarantined)
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
            stream.write(summary + "\n")
    return int(exit_code != 0)


if __name__ == "__main__":
    sys.exit(main())
