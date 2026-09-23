"""Security and failure behaviour of CI helpers, without GitHub writes or real outages."""

import base64
import io
import json
import os
import re
import runpy
import shutil
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
    assert scopes(["apps/mobile/lib/main.dart"]) == {
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
        "apps/ml-service/src/farmable_ml/forecast.py",
        "apps/ml-service/vision/train.py",
        "ml/forecast/validate_output.py",
        "ml/backtest/results/run.json",
    ],
)
def test_ml_implementation_and_adapter_changes_use_backend_scope(path):
    result = scopes([path])
    assert result["backend"]
    assert result["mobile"]
    assert result["any"]


def test_ml_adapter_only_uses_existing_backend_scope():
    result = scopes(["ml/forecast/test_forecast.py"])
    assert result["backend"]


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


def test_code_scanning_findings_are_not_hidden_by_successful_workflow():
    result = safe_result({"check": "codeql", "failed": False, "diagnostics": []})
    comment = render([result], [{"name": "CodeQL", "conclusion": "failure"}], 0)
    assert "### CodeQL" in comment and "code-scanning finding" in comment


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


def test_pr_checks_use_tested_merge_parent_instead_of_stale_event_base():
    repo = Path(__file__).resolve().parents[2]
    workflow = yaml.safe_load((repo / ".github/workflows/pr-checks.yml").read_text())
    scope_step = next(s for s in workflow["jobs"]["scopes"]["steps"] if s.get("id") == "paths")
    check_step = next(
        s for s in workflow["jobs"]["checks"]["steps"] if "CI_BASE" in s.get("env", {})
    )
    expected = (
        "${{ github.event_name == 'pull_request' && 'HEAD^1' "
        "|| github.event.before || 'HEAD^' }}"
    )
    assert scope_step["env"]["BASE"] == expected
    assert check_step["env"]["CI_BASE"] == expected


def test_mobile_e2e_bootstraps_a_standalone_build_and_real_offline_scenario():
    repo = Path(__file__).resolve().parents[2]
    workflow = yaml.safe_load((repo / ".github/workflows/pr-checks.yml").read_text())
    steps = workflow["jobs"]["e2e-mobile"]["steps"]
    java = next(step for step in steps if step.get("uses", "").startswith("actions/setup-java@"))
    assert (repo / java["with"]["cache-dependency-path"]).is_file()
    build = (repo / "scripts/ci-mobile.sh").read_text()
    # A release build, because a debug build needs a Dart VM service the E2E
    # harness does not provide; x86_64 only, because the CI emulator is x86_64.
    assert "flutter build apk --release" in build and "--debug" not in build
    assert "--target-platform android-x64" in build
    # Test mode replays recorded frames so camera screens run without a camera,
    # and it reaches the compiler from the same variable the guard reads.
    assert 'export TEST_MODE="${TEST_MODE:-true}"' in build
    assert "bash scripts/check-test-mode.sh" in build
    assert '--dart-define=TEST_MODE="$TEST_MODE"' in build
    assert '--dart-define=DEMO_MODE="$DEMO_MODE"' in build
    # The guard has to run before anything is compiled, or it is decoration.
    assert build.index("check-test-mode.sh") < build.index("flutter build apk")
    device_workflow = yaml.safe_load((repo / ".github/workflows/mobile.yml").read_text())
    device_steps = device_workflow["jobs"]["android-build"]["steps"]
    device_build = next(step for step in device_steps if step.get("name") == "Build the APK")
    # Physical test phones are ARM64; the emulator build above is separate.
    assert "--target-platform android-arm64" in device_build["run"]
    assert device_workflow["jobs"]["android-build"]["timeout-minutes"] == 30
    for step in steps:
        if "APK=" in step.get("with", {}).get("script", ""):
            assert "flutter-apk/app-release.apk" in step["with"]["script"]
    stack = (repo / "scripts/ci-stack.sh").read_text()
    online = stack.index("maestro test e2e/mobile/online_launch.yaml")
    stop = stack.index('"${compose[@]}" stop api')
    offline = stack.index("maestro test e2e/mobile/offline_launch.yaml")
    assert online < stop < offline


def test_mobile_maestro_flows_wait_for_release_app_startup():
    repo = Path(__file__).resolve().parents[2]
    for name in ("online_launch.yaml", "offline_launch.yaml"):
        flow = (repo / "e2e/mobile" / name).read_text()
        assert "extendedWaitUntil:" in flow
        # Matching the seeded farmer's name proves Home rendered the SEEDED farm
        # from local storage, not merely that some screen drew.
        #
        # The regex matters: Maestro matches the whole string, and the Android
        # accessibility tree Maestro reads merges sibling nodes, even though
        # Flutter's own semantics tree keeps them separate. A bare
        # "Hello, Sipho" silently never matches, which is exactly how this
        # passed review once and failed on a device.
        assert "visible: '.*Hello, Sipho.*'" in flow
        assert "id: 'sync-status'" in flow


def test_release_manifest_grants_network_access_and_scopes_cleartext():
    """A release APK must be able to reach the network, and only over HTTPS.

    `flutter create` declares INTERNET only in the debug and profile manifests,
    so a release build silently has no network at all while debug builds work.
    That failure mode reaches a real phone before anyone notices, so it is
    asserted here rather than left to the E2E job to rediscover.
    """
    repo = Path(__file__).resolve().parents[2]
    manifest = (repo / "apps/mobile/android/app/src/main/AndroidManifest.xml").read_text()
    assert 'android:name="android.permission.INTERNET"' in manifest

    # Cleartext is permitted only for the emulator's route to its host, never
    # globally: a farmer's phone must not be able to talk HTTP to anything.
    assert 'android:usesCleartextTraffic="true"' not in manifest
    assert 'android:networkSecurityConfig="@xml/network_security_config"' in manifest

    config = repo / "apps/mobile/android/app/src/main/res/xml/network_security_config.xml"
    assert config.is_file(), "referenced by the manifest, so it must be committed"
    policy = config.read_text()
    assert '<base-config cleartextTrafficPermitted="false" />' in policy
    assert "10.0.2.2" in policy


def test_flutter_native_sources_are_not_gitignored():
    """android/ and ios/ are committed source for Flutter, unlike under Expo.

    Ignoring them hides only *new* native files, because gitignore does not
    apply to already-tracked ones — so the repository looks healthy right up
    until someone adds a resource and the release build breaks in CI.
    """
    repo = Path(__file__).resolve().parents[2]
    ignored = (repo / ".gitignore").read_text()
    assert "apps/mobile/android/" not in ignored
    assert "apps/mobile/ios/" not in ignored


def test_privileged_reporter_never_checks_out_pr_code():
    repo = Path(__file__).resolve().parents[2]
    data = yaml.safe_load((repo / ".github/workflows/ci-report.yml").read_text())
    checkout = data["jobs"]["comment"]["steps"][0]
    assert checkout["with"]["ref"] == "${{ github.event.repository.default_branch }}"
    assert checkout["with"]["persist-credentials"] is False


def test_mobile_launch_failure_keeps_diagnostics_before_emulator_shutdown():
    repo = Path(__file__).resolve().parents[2]
    stack = (repo / "scripts/ci-stack.sh").read_text()
    assert 'if [ "$mode" = mobile ] && [ "$status" -ne 0 ]' in stack
    assert "AndroidRuntime:E flutter:E" in stack
    assert "adb exec-out screencap -p" in stack
    assert "uiautomator dump" in stack
    workflow = yaml.safe_load((repo / ".github/workflows/pr-checks.yml").read_text())
    diagnostic = next(
        step
        for step in workflow["jobs"]["e2e-mobile"]["steps"]
        if step.get("name") == "Preserve mobile launch diagnostics"
    )
    assert diagnostic["if"] == "failure() && steps.app.outputs.ready == 'true'"
    assert diagnostic["with"]["name"] == "mobile-e2e-debug"
    assert diagnostic["with"]["include-hidden-files"] is True
    assert diagnostic["with"]["path"].splitlines() == [".ci-mobile-debug/", "~/.maestro/tests/"]


def test_status_check_activation_defaults_to_read_only(monkeypatch, capsys):
    import required_checks

    api = Mock(side_effect=AssertionError("dry-run must not call GitHub"))
    monkeypatch.setattr(required_checks, "request_json", api)
    monkeypatch.setattr("sys.argv", ["required_checks.py"])
    required_checks.main()
    assert "Plan only" in capsys.readouterr().out
    api.assert_not_called()


@pytest.mark.parametrize("flutter_app", [True, False])
def test_status_check_activation_recognizes_flutter_and_preserves_checks(monkeypatch, flutter_app):
    import required_checks

    required = json.loads(Path(".github/required-checks.json").read_text())
    prefix = "/repos/example/repo"
    endpoint = prefix + "/branches/main/protection/required_status_checks"
    pubspec = "dependencies:\n  flutter:\n    sdk: flutter\n" if flutter_app else "dependencies: {}"
    replies = {
        prefix: {"permissions": {"admin": True}},
        prefix + "/issues/4": {"state": "closed"},
        prefix + "/contents/apps/mobile/pubspec.yaml?ref=main": {
            "content": base64.b64encode(pubspec.encode()).decode()
        },
        prefix + "/contents/e2e/mobile?ref=main": [{"name": "online.yaml", "type": "file"}],
        prefix + "/branches/main": {"commit": {"sha": "main-sha"}},
        endpoint: {"checks": [{"context": "existing-review", "app_id": 17}], "contexts": []},
    }
    writes = []

    def api(path, method="GET", payload=None):
        if method == "PATCH":
            writes.append((path, payload))
            return {}
        return replies[path]

    monkeypatch.setenv("GITHUB_REPOSITORY", "example/repo")
    monkeypatch.setattr("sys.argv", ["required_checks.py", "--apply"])
    monkeypatch.setattr(required_checks, "request_json", api)
    monkeypatch.setattr(
        required_checks,
        "all_pages",
        lambda *args: [
            {"id": index, "name": name, "conclusion": "success", "app": {"id": 99}}
            for index, name in enumerate(required)
        ],
    )
    if not flutter_app:
        with pytest.raises(RuntimeError, match="Flutter app"):
            required_checks.main()
        assert writes == []
        return

    required_checks.main()
    assert len(writes) == 1
    path, payload = writes[0]
    assert path == endpoint
    assert payload["strict"] is True
    assert {"context": "existing-review", "app_id": 17} in payload["checks"]
    assert all({"context": name, "app_id": 99} in payload["checks"] for name in required)


@pytest.mark.parametrize("approved", [False, True])
def test_main_migration_approval_comes_from_exact_merged_pr(monkeypatch, approved):
    import migration_safety

    monkeypatch.setenv("CI_MIGRATION_APPROVED", "false")
    monkeypatch.setenv("GITHUB_EVENT_NAME", "push")
    monkeypatch.setenv("GITHUB_SHA", "merged-sha")
    monkeypatch.setenv("GITHUB_REPOSITORY", "example/repo")
    monkeypatch.setenv("CI_BASE", "base-sha")
    monkeypatch.setenv("GH_TOKEN", "synthetic-read-only-token")
    api = Mock(
        return_value=[
            {
                "merged_at": "now",
                "merge_commit_sha": "merged-sha",
                "base": {"sha": "base-sha"},
                "labels": [{"name": "migration-approved"}] if approved else [],
            }
        ]
    )
    monkeypatch.setattr(migration_safety, "request_json", api)
    assert migration_safety.migration_approved() is approved
    api.assert_called_once_with("/repos/example/repo/commits/merged-sha/pulls")


@pytest.mark.parametrize(
    "field,value",
    [("merge_commit_sha", "other-commit"), ("base", {"sha": "other-base"}), ("merged_at", None)],
)
def test_unrelated_pr_cannot_approve_main_migrations(monkeypatch, field, value):
    import migration_safety

    monkeypatch.setenv("CI_MIGRATION_APPROVED", "false")
    monkeypatch.setenv("GITHUB_EVENT_NAME", "push")
    monkeypatch.setenv("GITHUB_SHA", "merged-sha")
    monkeypatch.setenv("GITHUB_REPOSITORY", "example/repo")
    monkeypatch.setenv("CI_BASE", "base-sha")
    monkeypatch.setenv("GH_TOKEN", "synthetic-read-only-token")
    pr = {
        "merged_at": "now",
        "merge_commit_sha": "merged-sha",
        "base": {"sha": "base-sha"},
        "labels": [{"name": "migration-approved"}],
        field: value,
    }
    monkeypatch.setattr(migration_safety, "request_json", Mock(return_value=[pr]))
    assert not migration_safety.migration_approved()


def _run_guard(**env):
    """The mode guard, run the way CI runs it, with the modes supplied by us."""
    repo = Path(__file__).resolve().parents[2]
    # Native Windows tests can select Git Bash instead of the WSL launcher.
    executable = os.environ.get("FARMABLE_TEST_BASH") or shutil.which("bash")
    if executable is None:
        pytest.skip("Bash is required for the build-mode guard tests")
    return subprocess.run(  # noqa: S603 - a fixed script, with modes passed as environment
        [executable, "scripts/check-test-mode.sh"],
        cwd=repo,
        # Inherited so bash can start at all, but with the two variables under
        # test always coming from the caller and never from the developer's shell.
        env={**{k: v for k, v in os.environ.items() if k not in ("TEST_MODE", "DEMO_MODE")}, **env},
        capture_output=True,
        text=True,
    )


@pytest.mark.parametrize(
    ("test_mode", "demo_mode"),
    [("true", "false"), ("false", "true"), ("false", "false")],
)
def test_one_build_mode_at_a_time_is_allowed(test_mode, demo_mode):
    result = _run_guard(TEST_MODE=test_mode, DEMO_MODE=demo_mode)
    assert result.returncode == 0, result.stderr


def test_a_build_asking_for_both_modes_is_refused():
    """The whole point of the guard: recorded detections must never be shown as live.

    It could not do this before. `ci-mobile.sh` passed TEST_MODE as a
    --dart-define, which is a compiler flag the script cannot read, and the
    script compared against "1" while Dart's bool.fromEnvironment only accepts
    the literal "true" — two independent reasons the two ends could never agree.
    """
    result = _run_guard(TEST_MODE="true", DEMO_MODE="true")
    assert result.returncode == 1
    assert "cannot both be set" in result.stderr


@pytest.mark.parametrize("value", ["1", "0", "True", "TRUE", "yes"])
def test_a_mode_dart_cannot_read_is_refused_rather_than_read_as_off(value):
    """`bool.fromEnvironment` recognises only `true`.

    Any other spelling compiles as false while looking set to a shell reading
    it, which is how a build could be handed TEST_MODE=1 and be neither in test
    mode nor reported as out of it.
    """
    result = _run_guard(TEST_MODE=value, DEMO_MODE="false")
    assert result.returncode == 1
    assert "must be exactly" in result.stderr


def test_the_guard_runs_against_the_values_the_device_builds_compile_in():
    """The workflow's builds and its guard must read one pair of variables."""
    repo = Path(__file__).resolve().parents[2]
    workflow = yaml.safe_load((repo / ".github/workflows/mobile.yml").read_text())
    assert workflow["env"]["TEST_MODE"] == "false"
    assert workflow["env"]["DEMO_MODE"] == "false"

    for job, name in (
        ("ios-unsigned-build", "Build without signing"),
        ("android-build", "Build the APK"),
    ):
        steps = workflow["jobs"][job]["steps"]
        build = next(step for step in steps if step.get("name") == name)
        run = build["run"]
        assert "check-test-mode.sh" in run
        assert '--dart-define=TEST_MODE="$TEST_MODE"' in run
        assert '--dart-define=DEMO_MODE="$DEMO_MODE"' in run
        assert run.index("check-test-mode.sh") < run.index("flutter build")
