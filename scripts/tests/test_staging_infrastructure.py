import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_gcp_stack_is_johannesburg_and_private() -> None:
    terraform = read("infra/gcp-staging.tf")
    for marker in (
        'default     = "africa-south1"',
        "google_artifact_registry_repository",
        "google_sql_database_instance",
        "POSTGRES_16",
        "google_storage_bucket",
        'public_access_prevention    = "enforced"',
        "uniform_bucket_level_access = true",
        'with_state                  = "ARCHIVED"',
        "days_since_noncurrent_time = 30",
        "google_secret_manager_secret",
        "google_iam_workload_identity_pool_provider",
        "token.actions.githubusercontent.com",
    ):
        assert marker in terraform
    assert "AWS::" not in terraform
    assert "serviceAccountKey" not in terraform


def test_wif_workflow_orders_backup_migration_and_rollout() -> None:
    workflow = read(".github/workflows/deploy-staging.yml")
    assert "id-token: write" in workflow
    assert "google-github-actions/auth@" in workflow
    assert "workload_identity_provider:" in workflow
    assert "service_account:" in workflow
    assert "serviceAccountKey" not in workflow
    assert "credentials_json" not in workflow
    assert "configure-aws-credentials" not in workflow
    assert workflow.index("gcp-backup.sh") < workflow.index("Apply approved Alembic migration")
    assert workflow.index("Apply approved Alembic migration") < workflow.index("gcp-rollout.sh")
    assert "IMAGE: ${{ steps.config.outputs.repository }}/backend:${{ github.sha }}" in workflow
    assert "--command=/app/cloudrun-migrate.sh" in workflow
    assert "DEPLOY_FREEZE != 'on'" in workflow
    assert "DEPLOY_FREEZE == 'on'" in workflow


def test_rollout_captures_traffic_and_rolls_back_on_negative_paths() -> None:
    rollout = read("infra/gcp-rollout.sh")
    assert "status.traffic" in rollout
    assert "previous_revision" in rollout
    assert "trap rollback ERR" in rollout
    assert "update-traffic" in rollout
    assert "health/ready" in rollout
    assert 'database == "ok" and .worker == "ok"' in rollout
    assert "sha // empty" in rollout
    assert "--no-traffic" in rollout
    assert '--to-revisions="${previous_revision}=100"' in rollout
    assert "gcloud run services delete" in rollout
    assert "service_existed" in rollout
    assert "must route 100% traffic to one revision" in rollout
    assert "--no-cpu-throttling" in rollout


def test_nightly_smoke_resolves_and_checks_the_live_ready_revision() -> None:
    workflow = read(".github/workflows/nightly-staging.yml")
    resolver = read("infra/gcp-live-config.sh")
    smoke = read("infra/gcp-demo-smoke.sh")
    assert "GCP_STAGING_URL" not in workflow
    assert "GCP_STAGING_SHA" not in workflow
    assert "GCP_PROJECT_ID" in workflow
    assert "gcp-live-config.sh" in workflow
    assert "status.traffic" in resolver
    assert ".percent == 100" in resolver
    assert "COMMIT_SHA" in resolver
    assert 'test("^[0-9a-f]{40}$")' in resolver
    assert '"$API_URL/health/live"' in smoke
    assert '"$API_URL/health/ready"' in smoke
    assert 'database == "ok" and .worker == "ok"' in smoke


@pytest.mark.skipif(shutil.which("jq") is None, reason="jq is required by deployment scripts")
def test_live_config_emits_the_ready_traffic_revision(tmp_path: Path) -> None:
    fake_gcloud = tmp_path / "gcloud"
    fake_gcloud.write_text(
        """#!/usr/bin/env bash
set -Eeuo pipefail
if [[ "$*" == *"run services describe"* ]]; then
  payload='{"status":{"url":"https://farmable.example",'
  payload+='"conditions":[{"type":"Ready","status":"True"}],'
  if [[ "${FAKE_SPLIT:-}" == true ]]; then
    payload+='"traffic":[{"revisionName":"farmable-00001","percent":50},'
    payload+='{"revisionName":"farmable-00002","percent":50}]}}'
  else
    payload+='"traffic":[{"revisionName":"farmable-00001","percent":100}]}}'
  fi
  printf '%s\n' "$payload"
elif [[ "$*" == *"run revisions describe farmable-00001"* ]]; then
  payload='{"spec":{"containers":[{"env":[{"name":"COMMIT_SHA",'
  payload+='"value":"0123456789abcdef0123456789abcdef01234567"}]}]},'
  payload+='"status":{"conditions":[{"type":"Ready","status":"True"}]}}'
  printf '%s\n' "$payload"
else
  exit 2
fi
""",
        encoding="utf-8",
    )
    fake_gcloud.chmod(0o755)
    output = tmp_path / "github-output"
    environment = {
        **os.environ,
        "PATH": f"{tmp_path}:{os.environ['PATH']}",
        "GCP_PROJECT": "farmable-project",
        "GCP_REGION": "africa-south1",
        "CLOUD_RUN_SERVICE": "farmable",
        "GITHUB_OUTPUT": str(output),
    }
    bash = shutil.which("bash")
    assert bash is not None
    result = subprocess.run(  # noqa: S603 - fixed shell and repository script
        [bash, str(ROOT / "infra/gcp-live-config.sh")],
        capture_output=True,
        check=False,
        env=environment,
        text=True,
    )
    assert result.returncode == 0, result.stderr
    assert output.read_text(encoding="utf-8").splitlines() == [
        "api_url=https://farmable.example",
        "commit_sha=0123456789abcdef0123456789abcdef01234567",
    ]
    environment["FAKE_SPLIT"] = "true"
    rejected = subprocess.run(  # noqa: S603 - fixed shell and repository script
        [bash, str(ROOT / "infra/gcp-live-config.sh")],
        capture_output=True,
        check=False,
        env=environment,
        text=True,
    )
    assert rejected.returncode != 0
    assert "exactly one revision" in rejected.stderr


def test_backup_verifies_completed_operation_before_returning() -> None:
    backup = read("infra/gcp-backup.sh")
    assert "--async" in backup
    assert "gcloud sql operations wait" in backup
    assert "status" in backup and '"$status" != "DONE"' in backup
    assert "DATABASE_URL" not in backup
    assert "password" not in backup.lower()
    assert 'role   = "roles/cloudsql.admin"' in read("infra/gcp-staging.tf")


def test_migration_job_initializes_app_and_worker_schemas() -> None:
    migration = read("infra/cloudrun-migrate.sh")
    assert "alembic upgrade head" in migration
    assert "farmable_backend.manage queue-schema" in migration


def test_secret_and_storage_smokes_do_not_print_values() -> None:
    secret = read("infra/gcp-secret-smoke.sh")
    storage = read("infra/gcp-storage-smoke.sh")
    assert "valueSource.secretKeyRef" in secret
    assert "service_json" in secret
    assert "gcloud storage cp" in storage
    assert "gcloud storage rm" in storage
    assert "--public" not in storage.lower()
    for path in (
        ".github/workflows/deploy-staging.yml",
        ".github/workflows/nightly-staging.yml",
        "infra/gcp-rollout.sh",
        "infra/gcp-secret-smoke.sh",
    ):
        content = read(path)
        assert "AKIA" not in content
        assert "ghp_" not in content
        assert "service-account.json" not in content


def test_old_aws_deployment_is_not_left_as_a_second_path() -> None:
    for path in (
        "infra/aws-staging.yaml",
        "infra/remote-deploy.sh",
        "infra/user-data.sh",
        "infra/Caddyfile",
        "infra/compose.staging.yaml",
    ):
        assert not (ROOT / path).exists(), path


def test_shell_contracts_parse() -> None:
    bash = shutil.which("bash")
    assert bash is not None
    for path in (
        "infra/cloudrun-entrypoint.sh",
        "infra/cloudrun-migrate.sh",
        "infra/gcp-backup.sh",
        "infra/gcp-demo-smoke.sh",
        "infra/gcp-live-config.sh",
        "infra/gcp-rollout.sh",
        "infra/gcp-secret-smoke.sh",
        "infra/gcp-storage-smoke.sh",
    ):
        result = subprocess.run(  # noqa: S603 - fixed shell parser and repository paths
            [bash, "-n", str(ROOT / path)], capture_output=True, text=True
        )
        assert result.returncode == 0, result.stderr
