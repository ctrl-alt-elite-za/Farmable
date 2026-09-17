"""Audit locked dependencies; fail high/critical and fail closed on unknown severity/errors."""

import json
import re
import shutil
import subprocess
import sys
import urllib.request
from pathlib import Path

from cvss import CVSS2, CVSS3, CVSS4


def severity(record: dict) -> float:
    named = {"LOW": 3.0, "MODERATE": 5.0, "MEDIUM": 5.0, "HIGH": 8.0, "CRITICAL": 9.5}
    scores = []
    name = record.get("database_specific", {}).get("severity", "").upper()
    if name in named:
        scores.append(named[name])
    for item in record.get("severity", []):
        constructors = {"CVSS_V2": CVSS2, "CVSS_V3": CVSS3, "CVSS_V4": CVSS4}
        if item["type"] in constructors:
            scores.append(float(constructors[item["type"]](item["score"]).scores()[0]))
    if not scores:
        raise ValueError("Unknown advisory severity")
    return max(scores)


def advisory(identifier: str) -> dict:
    if not re.fullmatch(r"(?:GHSA|PYSEC|CVE)-[A-Za-z0-9-]+", identifier):
        raise ValueError("Unexpected advisory identifier")
    with urllib.request.urlopen(  # noqa: S310 -- constant HTTPS service, validated path component.
        "https://api.osv.dev/v1/vulns/" + identifier, timeout=20
    ) as response:
        return json.load(response)


def python_high(report: dict, lookup=advisory) -> bool:
    if not isinstance(report.get("dependencies"), list):
        raise ValueError("Incomplete pip-audit output")
    high = False
    cache: dict[str, dict] = {}
    for package in report["dependencies"]:
        if "skip_reason" in package:
            raise ValueError("A locked dependency was not audited")
        for vuln in package.get("vulns", []):
            identifiers = [vuln["id"], *vuln.get("aliases", [])]
            identifiers.sort(key=lambda value: not value.startswith("GHSA-"))
            score = None
            for identifier in identifiers:
                if identifier not in cache:
                    cache[identifier] = lookup(identifier)
                try:
                    score = severity(cache[identifier])
                    break
                except ValueError:
                    continue
            if score is None:
                raise ValueError("No severity available for a known vulnerability")
            high = high or score >= 7.0
    return high


def node_high(report: dict) -> bool:
    if "error" in report or not isinstance(report.get("advisories"), dict):
        raise ValueError("Incomplete pnpm audit output")
    levels = {"low", "moderate", "high", "critical"}
    for item in report["advisories"].values():
        if item.get("severity") not in levels:
            raise ValueError("Unknown npm advisory severity")
    return any(item["severity"] in {"high", "critical"} for item in report["advisories"].values())


def run(command: list[str], output: Path | None = None) -> int:
    result = subprocess.run(  # noqa: S603
        command,
        capture_output=True,
        text=True,
        timeout=10 * 60,
        check=False,
    )
    if output is not None:
        output.write_text(result.stdout, encoding="utf-8")
    return result.returncode


def main() -> int:
    reports = Path(".ci-reports")
    reports.mkdir(exist_ok=True)
    requirements = reports / "requirements.txt"
    if (
        run(
            [
                "uv",
                "export",
                "--locked",
                "--no-emit-workspace",
                "--no-hashes",
                "--output-file",
                str(requirements),
            ]
        )
        != 0
    ):
        print("audit-unknown: could not export locked Python dependencies")
        return 1
    python_report = reports / "pip-audit.json"
    pip_status = run(
        [
            sys.executable,
            "-m",
            "pip_audit",
            "--no-deps",
            "--disable-pip",
            "--progress-spinner",
            "off",
            "--format",
            "json",
            "--output",
            str(python_report),
            "-r",
            str(requirements),
        ]
    )
    pnpm = shutil.which("pnpm")
    if pnpm is None:
        print("audit-unknown: pnpm is unavailable")
        return 1
    node_report = reports / "pnpm-audit.json"
    npm_status = run([pnpm, "audit", "--json"], node_report)
    if pip_status not in {0, 1} or npm_status not in {0, 1}:
        print("audit-unknown: dependency scanner did not complete")
        return 1
    try:
        python_failed = python_high(json.loads(python_report.read_text(encoding="utf-8")))
        node_failed = node_high(json.loads(node_report.read_text(encoding="utf-8")))
    except (ValueError, KeyError, OSError):
        print("audit-unknown: report or advisory severity unavailable; refusing a false pass")
        return 1
    if python_failed or node_failed:
        print("audit-high: high/critical vulnerabilities; upgrade dependencies and locks")
        return 1
    print("No high/critical dependency vulnerabilities found")
    return 0


if __name__ == "__main__":
    sys.exit(main())
