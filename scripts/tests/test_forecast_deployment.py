"""Execute the deployment wrappers against isolated tools; never call GCP."""

import os
import subprocess
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]


def run_script(tmp_path, script, *, failure="", mode="historical", missing=None):
    log = tmp_path / "calls"
    for name in ("docker", "gcloud"):
        tool = tmp_path / name
        tool.write_text(
            "#!/usr/bin/env bash\nset -euo pipefail\n"
            'printf "%s %s\\n" "${0##*/}" "$*" >> "$CALL_LOG"\n'
            'if [[ -n "$FAIL_COMMAND" && "$*" == *"$FAIL_COMMAND"* ]]; then exit 9; fi\n',
            encoding="utf-8",
        )
        tool.chmod(0o755)
    bash = os.environ.get("FARMABLE_TEST_BASH", "bash")
    environment = {
        **os.environ,
        "CALL_LOG": log.as_posix(),
        "FAIL_COMMAND": failure,
        "GCP_PROJECT": "farmable-project",
        "GCP_REGION": "africa-south1",
        "FORECAST_IMPORT_ACCOUNT": "import@farmable-project.iam.gserviceaccount.com",
        "RUNTIME_SERVICE_ACCOUNT": "runtime@farmable-project.iam.gserviceaccount.com",
        "DATABASE_SECRET": "database-url",
        "CLOUD_SQL_CONNECTION": "farmable-project:africa-south1:db",
        "FORECAST_GITHUB_TOKEN_SECRET": "forecast-github-token",
        "FORECAST_DATA_MODE": mode,
        "COMMIT_SHA": "a" * 40,
        "ARTIFACT_REPOSITORY": "africa-south1-docker.pkg.dev/farmable-project/repository",
        "API_URL": "https://demo.run.app",
    }
    if missing:
        environment.pop(missing)
    # Resolve POSIX timeout, not Windows timeout.exe, and keep fakes before gcloud.
    path = tmp_path.as_posix()
    if len(path) > 1 and path[1] == ":":
        path = "/" + path[0].lower() + path[2:]
    command = f'export PATH="{path}:$PATH"; bash {script}'
    result = subprocess.run(  # noqa: S603 -- fixed repo scripts and isolated fake tools.
        [bash, "-lc", command],
        cwd=ROOT,
        env=environment,
        capture_output=True,
        text=True,
        timeout=30,
    )
    return result, log.read_text() if log.exists() else ""


def test_post_migration_import_uses_separate_image_and_identity(tmp_path):
    result, calls = run_script(tmp_path, "infra/gcp-forecast-import.sh")
    assert result.returncode == 0, result.stderr
    assert "--target forecast-import" in calls
    assert (
        calls.index("docker build")
        < calls.index("docker push")
        < calls.index("jobs deploy")
        < calls.index("jobs execute")
    )
    assert "--service-account=import@" in calls
    assert "FORECAST_GITHUB_TOKEN=forecast-github-token:latest" in calls
    assert "--max-retries=0" in calls
    assert "--wait" in calls
    assert "farmable_backend.forecast_cli,import-latest,--root,/app/ml/forecast/results" in calls


@pytest.mark.parametrize("failure", ["build", "push", "jobs deploy", "jobs execute"])
def test_deploy_continues_when_import_fails(tmp_path, failure):
    result, calls = run_script(tmp_path, "infra/gcp-forecast-import.sh", failure=failure)
    assert result.returncode == 0
    assert "::warning::" in result.stdout
    assert "job completed" not in result.stdout
    if failure != "jobs execute":
        assert "jobs execute" not in calls  # Never execute a previous job after deploy failed.


def test_disabled_import_does_not_build_or_contact_cloud(tmp_path):
    result, calls = run_script(tmp_path, "infra/gcp-forecast-import.sh", mode="disabled")
    assert result.returncode == 0
    assert calls == ""
    assert "disabled" in result.stdout


@pytest.mark.parametrize("missing", ["FORECAST_IMPORT_ACCOUNT", "FORECAST_GITHUB_TOKEN_SECRET"])
def test_incomplete_import_setup_warns_before_any_cloud_call(tmp_path, missing):
    result, calls = run_script(tmp_path, "infra/gcp-forecast-import.sh", missing=missing)
    assert result.returncode == 0
    assert "::warning::" in result.stdout
    assert calls == ""


def test_nightly_smoke_uses_serving_sha_and_no_notification_secret(tmp_path):
    result, calls = run_script(tmp_path, "infra/gcp-outlook-smoke.sh")
    assert result.returncode == 0, result.stderr
    assert "/backend:" + "a" * 40 in calls
    assert "--service-account=runtime@" in calls
    assert "--args=-m,farmable_backend.outlook_smoke" in calls
    assert "FORECAST_GITHUB" not in calls
    assert "--max-retries=0" in calls and "--wait" in calls


@pytest.mark.parametrize("failure", ["jobs deploy", "jobs execute"])
def test_nightly_outlook_failure_fails_workflow(tmp_path, failure):
    result, calls = run_script(tmp_path, "infra/gcp-outlook-smoke.sh", failure=failure)
    assert result.returncode != 0
    if failure == "jobs deploy":
        assert "jobs execute" not in calls


def test_disabled_outlook_is_not_false_positive_nightly_acceptance(tmp_path):
    result, calls = run_script(tmp_path, "infra/gcp-outlook-smoke.sh", mode="disabled")
    assert result.returncode != 0
    assert calls == ""


def test_workflow_wiring_and_privilege_boundaries():
    deploy = yaml.safe_load((ROOT / ".github/workflows/deploy-staging.yml").read_text())
    steps = deploy["jobs"]["deploy"]["steps"]
    migration = next(
        i for i, step in enumerate(steps) if step.get("name") == "Apply approved Alembic migration"
    )
    importer = next(
        i for i, step in enumerate(steps) if step.get("run") == "bash infra/gcp-forecast-import.sh"
    )
    rollout = next(
        i for i, step in enumerate(steps) if step.get("run") == "bash infra/gcp-rollout.sh"
    )
    assert migration < importer < rollout
    assert (
        steps[importer]["env"]["FORECAST_DATA_MODE"] == steps[rollout]["env"]["FORECAST_DATA_MODE"]
    )
    assert "FORECAST_GITHUB_TOKEN_SECRET" not in steps[rollout]["env"]
    assert "secrets." not in str(steps[importer])  # References only; never credential values.
    assert deploy["permissions"] == {"contents": "read", "id-token": "write"}
    nightly = yaml.safe_load((ROOT / ".github/workflows/nightly-staging.yml").read_text())
    assert nightly["concurrency"] == deploy["concurrency"]
    smoke = nightly["jobs"]["smoke"]["steps"][-1]
    assert smoke["run"] == "bash infra/gcp-outlook-smoke.sh"
    assert smoke["env"]["COMMIT_SHA"] == "${{ steps.live.outputs.commit_sha }}"
    assert "if" not in smoke  # No silent skip when acceptance is unconfigured.


def test_import_artifacts_and_notifier_are_isolated_from_api():
    dockerfile = (ROOT / "apps/backend/Dockerfile").read_text()
    importer = dockerfile.split("FROM base AS forecast-import", 1)[1].split(
        "FROM base AS runtime", 1
    )[0]
    assert "COPY ml/forecast/results ml/forecast/results" in importer
    assert "fixtures" not in importer
    assert "ml/forecast" not in dockerfile.split("FROM base AS runtime", 1)[1]
    terraform = (ROOT / "infra/forecast-import.tf").read_text()
    assert "google_service_account.forecast_import.email" in terraform
    assert "google_service_account.runtime.email" not in terraform
    assert "secret_version" not in terraform  # Values are provisioned out of band.
    ci_stack = (ROOT / "scripts/ci-stack.sh").read_text()
    assert "docker build --file apps/backend/Dockerfile --target forecast-import ." in ci_stack
