"""Security and failure behaviour of CI helpers, without GitHub writes or real outages."""

import io
import json
import re
import runpy
import subprocess
import zipfile
from pathlib import Path
from unittest.mock import Mock

import pytest
import yaml
from audit_dependencies import node_high, python_high, severity
from ci_report import read_artifact, render, safe_result
from ci_run import diagnostics
from ci_scopes import scopes


@pytest.mark.parametrize("path", ["README.md", "docs/decisions/why.md", "AGENTS.md"])
def test_documentation_does_not_start_expensive_checks(path):
    assert not scopes([path])["any"]


@pytest.mark.parametrize(
    "path",
    [
        "uv.lock",
        "pnpm-lock.yaml",
        ".github/workflows/pr-checks.yml",
        "scripts/ci_run.py",
        "packages/api-client/src/index.ts",
        "migrations/versions/new.py",
        "infra/config.json",
    ],
)
def test_shared_changes_check_all_consumers(path):
    assert scopes([path])["backend"]
    assert scopes([path])["mobile"]


def test_mobile_only_does_not_build_backend():
    assert scopes(["apps/mobile/app.tsx"]) == {
        "backend": False,
        "mobile": True,
        "any": True,
        "assistant": False,
    }


def test_api_and_ml_changes_are_checked():
    for path in ["apps/backend/src/main.py", "apps/ml-service/forecast.py"]:
        assert scopes([path])["backend"]
        assert scopes([path])["mobile"]


@pytest.mark.parametrize(
    "path",
    [
        "backend/app/assistant/prompts.txt",
        "apps/backend/src/farmable_backend/assistant/gemini.py",
        "e2e/evals/assistant/cases/one.yaml",
    ],
)
def test_assistant_changes_require_evaluations(path):
    assert scopes([path])["assistant"]


def test_failure_report_has_reproduction_and_never_raw_secrets():
    raw = {
        "check": "typecheck",
        "failed": True,
        "diagnostics": ["type-error", "secret=password", "<script>"],
        "quarantined": [7, True, "password"],
        "log": "token=private-value",
    }
    result = safe_result(raw)
    comment = render([result], [], 0)
    assert "typecheck" in comment and "make typecheck" in comment
    assert "Compiler/type-check error" in comment and "#7" in comment
    for secret in ["password", "private-value", "<script>"]:
        assert secret not in comment


@pytest.mark.parametrize(
    "raw", [[], {"check": "../../anything", "failed": True}, {"check": "lint", "failed": "false"}]
)
def test_malformed_report_is_rejected(raw):
    with pytest.raises(ValueError):
        safe_result(raw)


def archive(data, filename="typecheck.json"):
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w") as output:
        output.writestr(filename, json.dumps(data))
    return buffer.getvalue()


def test_untrusted_artifacts_are_only_data():
    data = {"check": "typecheck", "failed": True, "diagnostics": ["type-error"]}
    assert read_artifact(archive(data))[0]["diagnostics"] == ["type-error"]
    assert read_artifact(archive({"command": "execute"}, "run.py")) == []
    with pytest.raises(ValueError):
        read_artifact(archive({"check": "lint", "failed": True, "log": "x" * 20_000}, "lint.json"))


def test_dangerous_migration_report_names_statement_and_label():
    result = safe_result(
        {"check": "migration-safety", "failed": True, "diagnostics": ["drop-column"]}
    )
    comment = render([result], [], 0)
    assert "DROP COLUMN" in comment and "migration-approved" in comment


def test_timeout_quarantine_and_missing_mobile_are_visible():
    result = safe_result(
        {
            "check": "e2e-mobile",
            "failed": False,
            "diagnostics": ["prerequisite"],
            "quarantined": [4],
        }
    )
    comment = render([result], [{"name": "typecheck", "conclusion": "timed_out"}], 0)
    assert "Stuck step: `Run typecheck`" in comment
    assert "#4" in comment and "NOT VERIFIED" in comment
    assert "30-minute" in comment


def test_secret_findings_include_rotation_guidance():
    comment = render([], [{"name": "gitleaks", "conclusion": "failure"}], 0)
    assert "rotate" in comment and "history" in comment


def test_audit_report_explains_dependabot_status():
    failed = [{"name": "security-audit", "conclusion": "failure"}]
    assert "No open Dependabot" in render([], failed, 0)
    assert "2 open Dependabot" in render([], failed, 2)


def test_diagnostics_are_fixed_enums_not_log_text():
    output = "error: private-value [assignment]\nDROP COLUMN farmer_phone;\nSECRET=private-value"
    assert diagnostics(output) == ["type-error", "drop-column"]


@pytest.mark.parametrize(
    "level,expected", [("LOW", 3), ("MODERATE", 5), ("HIGH", 8), ("CRITICAL", 9.5)]
)
def test_osv_named_severity(level, expected):
    assert severity({"database_specific": {"severity": level}}) == expected


def test_cvss_severity_and_unknown_fail_closed():
    assert (
        severity(
            {
                "severity": [
                    {"type": "CVSS_V3", "score": "CVSS:3.1/AV:N/AC:L/PR:N/UI:N/S:U/C:H/I:H/A:H"}
                ]
            }
        )
        == 9.8
    )
    with pytest.raises(ValueError):
        severity({})


@pytest.mark.parametrize(
    "level,blocked", [("low", False), ("moderate", False), ("high", True), ("critical", True)]
)
def test_node_audit_threshold(level, blocked):
    assert node_high({"advisories": {"123": {"severity": level}}}) == blocked


def test_failed_scanners_cannot_pass():
    with pytest.raises(ValueError):
        node_high({"error": "unavailable"})
    with pytest.raises(ValueError):
        python_high({})
    with pytest.raises(ValueError):
        python_high({"dependencies": [{"skip_reason": "unsupported"}]})


@pytest.mark.parametrize("level,blocked", [("MODERATE", False), ("HIGH", True), ("CRITICAL", True)])
def test_python_audit_threshold_and_alias_cache(level, blocked):
    vuln = {"id": "PYSEC-2026-1", "aliases": ["GHSA-xxxx-yyyy-zzzz"]}
    lookup = Mock(return_value={"database_specific": {"severity": level}})
    assert python_high({"dependencies": [{"vulns": [vuln, vuln]}]}, lookup) == blocked
    lookup.assert_called_once_with("GHSA-xxxx-yyyy-zzzz")


def test_migration_base_heads_are_read_without_executing_code(monkeypatch):
    import migration_safety

    def git(*args):
        if args[0] == "ls-tree":
            return "migrations/versions/a.py\nmigrations/versions/b.py\n"
        if args[1].endswith("a.py"):
            return (
                'revision: str = "a"\ndown_revision = None\nraise RuntimeError("must not execute")'
            )
        return 'revision = "b"\ndown_revision = "a"'

    monkeypatch.setattr(migration_safety, "git", git)
    assert migration_safety.base_head("test-base") == "b"


def test_immutable_migration_cannot_be_label_bypassed(monkeypatch):
    import migration_safety

    monkeypatch.setattr(migration_safety, "git", lambda *args: "M\tmigrations/versions/a.py")
    monkeypatch.setenv("CI_MIGRATION_APPROVED", "true")
    assert migration_safety.main() == 1


def test_check_run_writes_safe_failure_artifact(tmp_path, monkeypatch):
    import ci_run

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(ci_run.shutil, "which", lambda name: "/tools/make")
    monkeypatch.setattr(
        ci_run.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args, 1, "error: secret [assignment]", ""
        ),
    )
    monkeypatch.setattr("sys.argv", ["ci_run.py", "typecheck"])
    assert ci_run.main() == 1
    result = json.loads((tmp_path / ".ci-reports/typecheck.json").read_text())
    assert result["failed"] and result["diagnostics"] == ["type-error"]
    assert "secret" not in json.dumps(result)


@pytest.mark.parametrize(
    "level,approved,expected",
    [
        ("Warning", False, 1),
        ("Warning", True, 0),
        ("Error", False, 1),
        ("Error", True, 1),
    ],
)
def test_migration_approval_only_bypasses_valid_warnings(
    tmp_path, monkeypatch, level, approved, expected
):
    import migration_safety

    monkeypatch.chdir(tmp_path)
    monkeypatch.setattr(migration_safety, "git", lambda *args: "")
    monkeypatch.setattr(migration_safety, "base_head", lambda base: "0001")
    monkeypatch.setattr(migration_safety.shutil, "which", lambda name: "/tools/uvx")
    monkeypatch.setattr(migration_safety.command, "upgrade", lambda *args, **kwargs: None)
    monkeypatch.setattr(
        migration_safety.subprocess,
        "run",
        lambda *args, **kwargs: subprocess.CompletedProcess(
            args, 1, json.dumps([{"level": level}]), ""
        ),
    )
    monkeypatch.setenv("CI_MIGRATION_APPROVED", str(approved).lower())
    assert migration_safety.main() == expected


@pytest.mark.parametrize("issue", [None, True, -1, 0, "123"])
def test_quarantine_without_valid_issue_fails_collection(issue):
    hook = runpy.run_path(str(Path(__file__).resolve().parents[2] / "conftest.py"))
    item = Mock()
    item.get_closest_marker.return_value = pytest.mark.quarantine(issue=issue).mark
    with pytest.raises(pytest.UsageError):
        hook["pytest_collection_modifyitems"]([item])


def test_valid_quarantine_skips_with_linked_issue():
    hook = runpy.run_path(str(Path(__file__).resolve().parents[2] / "conftest.py"))
    item = Mock()
    item.get_closest_marker.return_value = pytest.mark.quarantine(issue=123).mark
    hook["pytest_collection_modifyitems"]([item])
    assert item.add_marker.call_args.args[0].kwargs["reason"] == "quarantined: #123"


def test_every_remote_action_is_sha_pinned_and_jobs_are_bounded():
    repo = Path(__file__).resolve().parents[2]
    for path in (repo / ".github").rglob("*.yml"):
        data = yaml.safe_load(path.read_text())
        if "jobs" in data:
            assert data["permissions"]["contents"] == "read"
            assert "pull_request_target" not in data.get("on", data.get(True, {}))
            jobs = data["jobs"].values()
        else:
            jobs = [data["runs"]] if "runs" in data else []
        for job in jobs:
            if "runs-on" in job:
                assert job["timeout-minutes"] == 30
            if job.get("permissions", {}).get("contents") == "write":
                assert path.name == "autofix.yml"
            if job.get("permissions", {}).get("pull-requests") == "write":
                assert path.name == "ci-report.yml"
            for step in job.get("steps", []):
                action = step.get("uses", "")
                if action and not action.startswith("./"):
                    assert re.fullmatch(r"[^@]+@[0-9a-f]{40}", action), (path, action)


def test_privileged_reporter_never_checks_out_pr_code():
    repo = Path(__file__).resolve().parents[2]
    data = yaml.safe_load((repo / ".github/workflows/ci-report.yml").read_text())
    checkout = data["jobs"]["comment"]["steps"][0]
    assert checkout["with"]["ref"] == "${{ github.event.repository.default_branch }}"
    assert checkout["with"]["persist-credentials"] is False


def test_status_check_activation_defaults_to_read_only(monkeypatch, capsys):
    import required_checks

    api = Mock(side_effect=AssertionError("dry-run must not call GitHub"))
    monkeypatch.setattr(required_checks, "request_json", api)
    monkeypatch.setattr("sys.argv", ["required_checks.py"])
    required_checks.main()
    assert "Plan only" in capsys.readouterr().out
    api.assert_not_called()
