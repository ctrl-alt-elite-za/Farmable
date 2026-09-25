import json
import os
import re
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).parents[2]

# The deployment scripts require jq. Skipping locally is a convenience; skipping in
# CI would let these assertions silently not run, which is the same failure mode --
# a check that reports green without exercising anything -- that the substring greps
# these tests replaced had.
requires_jq = pytest.mark.skipif(
    shutil.which("jq") is None and not os.environ.get("GITHUB_ACTIONS"),
    reason="jq is required by the deployment scripts; install it to run this locally",
)


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def test_gcp_stack_is_johannesburg_and_private() -> None:
    terraform = read("infra/gcp-staging.tf")
    for marker in (
        'default     = "africa-south1"',
        "google_artifact_registry_repository",
        "google_sql_database_instance",
        'edition           = "ENTERPRISE"',
        "POSTGRES_16",
        "google_storage_bucket",
        'public_access_prevention    = "enforced"',
        "uniform_bucket_level_access = true",
        'with_state                 = "ARCHIVED"',
        "days_since_noncurrent_time = 30",
        "google_secret_manager_secret",
        "google_iam_workload_identity_pool_provider",
        "for_each  = local.provider_secrets",
        "token.actions.githubusercontent.com",
    ):
        assert marker in terraform
    # Matched on structure, not on column alignment. Pinning the exact run of spaces
    # meant `terraform fmt` -- which the runbook tells operators to run -- broke this
    # test, so the formatter and the contract disagreed about the same file.
    assert re.search(r'with_state\s*=\s*"ARCHIVED"', terraform)
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


@requires_jq
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
        "PATH": _path(tmp_path),
        "GCP_PROJECT": "farmable-project",
        "GCP_REGION": "africa-south1",
        "CLOUD_RUN_SERVICE": "farmable",
        "GITHUB_OUTPUT": str(output),
    }
    bash = _bash()
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


def test_deployer_may_list_the_secrets_the_rollout_discovers() -> None:
    """The rollout discovers which provider secrets hold an enabled version before
    wiring them, so the deployer needs Secret Manager *metadata* reads.

    `roles/secretmanager.secretAccessor` does not cover this: it grants
    `secretmanager.versions.access` and nothing else, and it is bound to the runtime
    account rather than the deployer. Without a metadata grant the discovery call fails
    closed and the deploy aborts before `gcloud run deploy` -- so the permission and the
    script that depends on it are asserted together, from the verbs actually used.
    """
    rollout = read("infra/gcp-rollout.sh")
    terraform = read("infra/gcp-staging.tf")

    verbs = {
        "gcloud secrets list": "secretmanager.secrets.list",
        "gcloud secrets versions list": "secretmanager.versions.list",
    }
    used = {command for command in verbs if command in rollout}
    assert used, "the rollout no longer discovers secrets; drop this test with the grant"

    block = re.search(
        r'resource\s+"google_project_iam_member"\s+"deployer_secret_viewer"\s*\{(.*?)\n\}',
        terraform,
        re.DOTALL,
    )
    assert block, "the deployer has no Secret Manager metadata grant"
    # Assert on what the block grants, not on its prose: the comment explains why
    # secretAccessor is the wrong role, and that explanation must not read as a grant.
    granted = "\n".join(
        line for line in block.group(1).splitlines() if not line.lstrip().startswith("#")
    )
    # viewer carries secrets.list and versions.list; it does not carry versions.access.
    assert re.search(r'role\s*=\s*"roles/secretmanager\.viewer"', granted)
    assert "google_service_account.deployer.email" in granted
    # The deployer reads which secrets exist, never what any of them contains.
    assert "secretAccessor" not in granted


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
    bash = _bash()
    for path in (
        "infra/cloudrun-entrypoint.sh",
        "infra/cloudrun-migrate.sh",
        "infra/gcp-backup.sh",
        "infra/gcp-demo-smoke.sh",
        "infra/gcp-live-config.sh",
        "infra/gcp-rollout.sh",
        "infra/gcp-secret-smoke.sh",
        "infra/gcp-storage-smoke.sh",
        "infra/gcp-required-config.sh",
        "infra/gcp-verify-setup.sh",
    ):
        result = subprocess.run(  # noqa: S603 - fixed shell parser and repository paths
            [bash, "-n", str(ROOT / path)], capture_output=True, text=True
        )
        assert result.returncode == 0, result.stderr


def _bash() -> str:
    found = shutil.which("bash")
    assert found is not None
    return found


def _log_calls(log: Path) -> str:
    """Shell that appends every invocation's arguments to `log`.

    Hand-copied into three stubs before this existed, and one copy had already drifted
    to a different newline encoding -- the duplication was not being kept in sync.
    """
    return "printf '%s\\n' \"$*\" >>" + f'"{log}"\n'


def _fake_gcloud(tmp_path: Path, body: str) -> None:
    script = tmp_path / "gcloud"
    script.write_text("#!/usr/bin/env bash\nset -Eeuo pipefail\n" + body, encoding="utf-8")
    script.chmod(0o755)


def _run(script: str, environment: dict) -> "subprocess.CompletedProcess[str]":
    return subprocess.run(  # noqa: S603 - fixed shell and repository script
        [_bash(), str(ROOT / script)],
        capture_output=True,
        check=False,
        env=environment,
        text=True,
    )


def _path(tmp_path: Path) -> str:
    return f"{tmp_path}{os.pathsep}{os.environ['PATH']}"


REFERENCE_ENV_V1 = (
    '{"name":"DATABASE_URL","valueFrom":{"secretKeyRef":'
    '{"name":"farmable-staging-database-url","key":"latest"}}},'
    '{"name":"GEMINI_API_KEY","valueFrom":{"secretKeyRef":'
    '{"name":"farmable-staging-gemini-api-key","key":"latest"}}},'
    '{"name":"EXPORT_TOKEN_SECRET","valueFrom":{"secretKeyRef":'
    '{"name":"farmable-staging-export-token-secret","key":"latest"}}}'
)
LITERAL_ENV = (
    '{"name":"DATABASE_URL","value":"postgresql://user:pw@host/db"},'
    '{"name":"GEMINI_API_KEY","value":"AIzaSyFAKE"}'
)


def _service_spec(env_json: str) -> str:
    """The `spec` half of a Knative v1 service, as the single source of that nesting."""
    return '{"spec":{"template":{"spec":{"containers":[{"env":[' + env_json + "]}]}}}}"


def _describe_body(env_json: str) -> str:
    """Knative v1 nests containers under spec.template.spec, per run_v1_messages:
    ServiceSpec.template -> RevisionTemplate -> RevisionSpec.containers. Writing the
    real path matters even though gcp-secret-smoke.sh searches with `..`: a fixture
    on a made-up path cannot catch a regression that makes the query path-sensitive.
    """
    return "cat <<'FAKEJSON'\n" + _service_spec(env_json) + "\nFAKEJSON\n"


def _secret_env(tmp_path: Path) -> dict:
    return {
        **os.environ,
        "PATH": _path(tmp_path),
        "GCP_PROJECT": "farmable-project",
        "GCP_REGION": "africa-south1",
        "CLOUD_RUN_SERVICE": "farmable",
    }


@requires_jq
def test_secret_smoke_accepts_knative_v1_secret_references(tmp_path: Path) -> None:
    """`gcloud run services describe` issues a RunNamespacesServicesGetRequest --
    the Knative v1 API -- so a secret-backed env var is
    EnvVar.valueFrom -> EnvVarSource.secretKeyRef -> SecretKeySelector{name, key}.
    That is the one shape the assertion needs to accept.
    """
    _fake_gcloud(tmp_path, _describe_body(REFERENCE_ENV_V1))
    result = _run("infra/gcp-secret-smoke.sh", _secret_env(tmp_path))
    assert result.returncode == 0, result.stderr


@requires_jq
def test_secret_smoke_rejects_plaintext_secret_env_vars(tmp_path: Path) -> None:
    _fake_gcloud(tmp_path, _describe_body(LITERAL_ENV))
    result = _run("infra/gcp-secret-smoke.sh", _secret_env(tmp_path))
    assert result.returncode != 0
    assert "postgresql://" not in result.stdout + result.stderr


def test_migrate_script_runs_alembic_without_resyncing_the_venv(tmp_path: Path) -> None:
    """`uv run` re-syncs the project before executing the command. In the runtime
    image /app/.venv is created by root and the process runs as `farmable`
    (Dockerfile:14,21), so that re-sync is EACCES and the migration job fails every
    time. A `uv` on PATH that refuses to run is what makes this test fail if
    `uv run` ever returns to the script.
    """
    log = tmp_path / "calls.log"
    for name in ("alembic", "python"):
        stub = tmp_path / name
        stub.write_text(
            "#!/usr/bin/env bash\nprintf '%s %s\\n' " + name + ' "$*" >>"' + str(log) + '"\n',
            encoding="utf-8",
        )
        stub.chmod(0o755)
    uv = tmp_path / "uv"
    uv.write_text(
        "#!/usr/bin/env bash\necho 'uv must not run in the migration job' >&2\nexit 97\n",
        encoding="utf-8",
    )
    uv.chmod(0o755)

    result = _run("infra/cloudrun-migrate.sh", {**os.environ, "PATH": _path(tmp_path)})
    assert result.returncode == 0, result.stderr
    calls = log.read_text(encoding="utf-8")
    assert "alembic upgrade head" in calls
    assert "farmable_backend.manage queue-schema" in calls


def _rollout_env(tmp_path: Path) -> dict:
    return {
        **os.environ,
        "PATH": _path(tmp_path),
        "GCP_PROJECT": "farmable-project",
        "GCP_REGION": "africa-south1",
        "CLOUD_RUN_SERVICE": "farmable",
        "IMAGE": "africa-south1-docker.pkg.dev/p/r/backend:abc",
        "COMMIT_SHA": "0123456789abcdef0123456789abcdef01234567",
        "CLOUD_SQL_CONNECTION": "farmable-project:africa-south1:farmable-staging",
        "RUNTIME_SERVICE_ACCOUNT": "runtime@farmable-project.iam.gserviceaccount.com",
        "DATABASE_SECRET": "farmable-staging-database-url",
        "EXPORT_SECRET": "farmable-staging-export-token-secret",
        "GEMINI_SECRET": "farmable-staging-gemini-api-key",
        "GCS_BUCKET": "farmable-project-farmable-staging-media",
    }


def test_rollout_aborts_when_describe_fails_for_any_reason_but_not_found(tmp_path: Path) -> None:
    """A transient 503 must not be read as "the service does not exist". Concluding
    absence sets service_existed=false, which arms the `gcloud run services delete`
    rollback branch against a service that is live and serving traffic.
    """
    _fake_gcloud(
        tmp_path,
        'if [[ "$*" == *"run services list"* ]]; then\n'
        "  echo 'ERROR: (gcloud.run.services.list) HTTPError 503: backend error' >&2\n"
        "  exit 1\n"
        "fi\n"
        "exit 0\n",
    )
    result = _run("infra/gcp-rollout.sh", _rollout_env(tmp_path))
    assert result.returncode != 0
    assert "could not determine" in result.stderr.lower()


def test_rollout_treats_not_found_as_a_first_deployment(tmp_path: Path) -> None:
    log = tmp_path / "calls.log"
    _fake_gcloud(
        tmp_path,
        'printf \'%s\\n\' "$*" >>"' + str(log) + '"\n'
        # An absent service is empty stdout and a zero exit, not an error -- but real
        # gcloud still writes notices to stderr, so a probe that merged the streams
        # would read this service as present and never reach the deploy.
        'if [[ "$*" == *"run services list"* ]]; then\n'
        "  echo 'Updates are available for some Google Cloud CLI components.' >&2\n"
        "  exit 0\n"
        "fi\n"
        'if [[ "$*" == *"secrets list"* ]]; then\n'
        "  printf '%s\\n' 'farmable-staging-export-token-secret'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"secrets versions list"* ]]; then\n'
        "  printf '%s\\n' "
        "'projects/farmable-project/secrets/"
        "farmable-staging-export-token-secret/versions/1'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"run deploy"* ]]; then exit 42; fi\n'
        "exit 0\n",
    )
    result = _run("infra/gcp-rollout.sh", _rollout_env(tmp_path))
    # Deliberately no assertion on returncode: the fake chooses that exit code, so
    # asserting it would test the fixture rather than the script. Reaching the deploy
    # is the behaviour under test.
    assert "run deploy" in log.read_text(encoding="utf-8"), result.stderr


# A `gcloud run services list --format='value(a,b)'` prints the requested fields in
# order, tab separated, leaving a field blank when the resource does not carry it.
# Honouring --format rather than printing a canned row is what lets these tests catch
# a probe that asks for the wrong identifier field: under the encoding that does not
# populate it, the output is blank, which reads as "the service does not exist".
_LIST_STUB = r"""
# `gcloud run services list --filter=metadata.name=X --format=value(metadata.name)`
# prints the name when the service exists and nothing when it does not. Honouring
# both flags -- rather than printing a canned row -- is what lets these tests catch a
# probe that filters or projects on the wrong field: under a wrong field the output is
# blank, which the script reads as "the service does not exist".
if [[ "$*" == *"run services list"* ]]; then
  echo 'Updates are available for some Google Cloud CLI components.' >&2
  if [[ "$*" == *"metadata.name=${FAKE_SERVICE:-farmable}"* \
        && "$*" == *"value(metadata.name)"* ]]; then
    printf '%s\n' "${FAKE_SERVICE:-farmable}"
  fi
  exit 0
fi
"""


@requires_jq
def test_rollout_reads_existing_traffic_when_the_service_is_present(
    tmp_path: Path,
) -> None:
    """The "service exists" branch is where a misread is dangerous: concluding absence
    here is what arms `gcloud run services delete`. Split traffic is the cheapest
    observable proof that the branch was entered and the traffic block was parsed --
    if the probe reads the service as absent, the script deploys instead and this
    assertion fails.
    """
    _fake_gcloud(
        tmp_path,
        _LIST_STUB + 'if [[ "$*" == *"run services describe"* ]]; then\n'
        "  cat <<'FAKEJSON'\n"
        '{"status":{"traffic":[{"revisionName":"farmable-00001","percent":50},'
        '{"revisionName":"farmable-00002","percent":50}]}}\n'
        "FAKEJSON\n"
        "  exit 0\n"
        "fi\n"
        "exit 0\n",
    )
    result = _run("infra/gcp-rollout.sh", _rollout_env(tmp_path))
    assert result.returncode != 0
    assert "must route 100% traffic to one revision" in result.stderr


def test_terraform_state_is_ignored() -> None:
    """infra/README.md documents a local `terraform apply` with no remote backend,
    so state lands in the working tree. State records full resource attributes for
    Secret Manager and Cloud SQL.
    """
    ignored = read("infra/.gitignore")
    assert "*.tfstate" in ignored
    assert "*.tfstate.backup" in ignored


def test_deploy_freeze_is_documented_as_a_repository_variable() -> None:
    """A job-level `if:` is evaluated before the job's environment is resolved, so
    an environment-scoped variable is invisible there. The `frozen` job also
    declares no environment at all, so the two jobs cannot read the same variable
    set. Repository scope is the one place both `if:` expressions can see.
    """
    readme = read("infra/README.md")
    assert "repository variable" in readme
    assert "protected environment" not in readme


def _backup_env(tmp_path: Path) -> dict:
    return {
        **os.environ,
        "PATH": _path(tmp_path),
        "GCP_PROJECT": "farmable-project",
        "CLOUD_SQL_INSTANCE": "farmable-staging",
        "COMMIT_SHA": "0123456789abcdef0123456789abcdef01234567",
    }


def test_backup_does_not_pass_unsupported_flags_to_sql_operations(tmp_path: Path) -> None:
    """`gcloud sql operations wait|describe` take OPERATION plus wide flags only --
    verified against gcloud 585.0.0, whose synopsis is
    `gcloud sql operations wait OPERATION [OPERATION ...] [--timeout=TIMEOUT]`.
    Passing --instance is an unrecognised argument, which under `set -Eeuo pipefail`
    aborts the backup step and therefore every deploy, before the migration runs.

    The fake rejects unknown flags the way a real CLI does, so this fails if an
    unsupported flag is passed to either subcommand.
    """
    log = tmp_path / "calls.log"
    _fake_gcloud(
        tmp_path,
        'printf \'%s\n\' "$*" >>"' + str(log) + '"\n'
        'if [[ "$*" == *"sql operations"* ]]; then\n'
        '  for arg in "$@"; do\n'
        '    case "$arg" in\n'
        "      --instance=*|--instance)\n"
        '        echo "ERROR: unrecognized arguments: $arg" >&2\n'
        "        exit 2 ;;\n"
        "    esac\n"
        "  done\n"
        "fi\n"
        'if [[ "$*" == *"sql backups create"* ]]; then\n'
        "  printf '%s\\n' 'operation-abc123'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"operations describe"* ]]; then\n'
        '  if [[ "$*" == *"error.errors"* ]]; then exit 0; fi\n'
        "  printf '%s\\n' 'DONE'; exit 0\n"
        "fi\n"
        "exit 0\n",
    )
    result = _run("infra/gcp-backup.sh", _backup_env(tmp_path))
    assert result.returncode == 0, result.stderr
    assert "unrecognized arguments" not in result.stderr


_READY_JSON = (
    '{"sha":"0123456789abcdef0123456789abcdef01234567","status":"ok",'
    '"database":"ok","worker":"ok"}'
)


def _fake_curl(tmp_path: Path) -> None:
    """Serves the readiness/liveness contract gcp-rollout.sh and gcp-demo-smoke.sh
    poll, so the successful path can run to completion offline."""
    curl = tmp_path / "curl"
    curl.write_text(
        "#!/usr/bin/env bash\n"
        'url="${!#}"\n'
        'case "$url" in\n'
        "  *openapi.json) printf '%s\\n' '{\"paths\":{\"/health/ready\":{}}}' ;;\n"
        "  *) printf '%s\\n' '" + _READY_JSON + "' ;;\n"
        "esac\n",
        encoding="utf-8",
    )
    curl.chmod(0o755)


_STORAGE_STUB = r"""
# gcp-storage-smoke.sh uploads, downloads and diffs a file, so a fake that merely
# exits 0 leaves an empty download and the diff fails. Move the bytes through a
# local stand-in for the bucket. Flags are skipped because `gcloud storage cp`
# is called with a trailing --quiet, so the paths are not simply the last two args.
if [[ "$*" == *"storage cp"* ]]; then
  positional=()
  for a in "$@"; do
    case "$a" in --*) ;; *) positional+=("$a") ;; esac
  done
  resolve() {
    case "$1" in
      gs://*) printf '%s\n' "${FAKE_BUCKET}/${1#gs://}" ;;
      *) printf '%s\n' "$1" ;;
    esac
  }
  src="$(resolve "${positional[-2]}")"
  dst="$(resolve "${positional[-1]}")"
  mkdir -p "$(dirname "$dst")"
  cp "$src" "$dst"
  exit 0
fi
if [[ "$*" == *"storage rm"* ]]; then exit 0; fi
"""


@requires_jq
@pytest.mark.parametrize("latest_revision", ["farmable-00002", "farmable-unrelated"])
def test_rollout_shifts_traffic_to_the_new_revision_on_the_successful_path(
    tmp_path: Path,
    latest_revision: str,
) -> None:
    """Exercise readiness and all smokes before promoting the tagged revision.

    An unrelated deployment can advance the service-wide latest revision without
    changing our commit tag. That unrelated revision must never receive traffic.
    """
    log = tmp_path / "calls.log"
    sha = "0123456789abcdef0123456789abcdef01234567"
    # Reuse the one place the Knative v1 container/env nesting is spelled out, so a
    # correction there cannot leave a stale second copy here.
    service_json = (
        '{"status":{"traffic":[{"tag":"sha-' + sha + '",'
        '"url":"https://sha-' + sha[:8] + '---farmable.run.app",'
        '"revisionName":"farmable-00002"}]},' + _service_spec(REFERENCE_ENV_V1)[1:]
    )
    _fake_gcloud(
        tmp_path,
        _log_calls(log)
        # First deploy: no existing service.
        + 'if [[ "$*" == *"run services list"* ]]; then exit 0; fi\n'
        'if [[ "$*" == *"latestCreatedRevisionName"* ]]; then\n'
        f"  printf '%s\\n' '{latest_revision}'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"run services describe"* ]]; then\n'
        "  cat <<'FAKEJSON'\n" + service_json + "\nFAKEJSON\n"
        "  exit 0\n"
        "fi\n" + _STORAGE_STUB + "exit 0\n",
    )
    _fake_curl(tmp_path)

    bucket = tmp_path / "bucket"
    bucket.mkdir()
    environment = {**_rollout_env(tmp_path), "FAKE_BUCKET": str(bucket)}
    result = _run("infra/gcp-rollout.sh", environment)
    assert result.returncode == 0, result.stderr + result.stdout
    calls = log.read_text(encoding="utf-8")
    assert "run deploy" in calls
    deploy_call = calls.split("run deploy", 1)[1].split("\n", 1)[0]
    assert "--no-traffic" not in deploy_call
    assert "update-traffic" in calls
    assert "farmable-00002=100" in calls
    assert "farmable-unrelated=100" not in calls
    # A successful rollout must never touch the delete path.
    assert "services delete" not in calls
    assert f"Cloud Run deployed {sha}" in result.stdout


@requires_jq
@pytest.mark.parametrize(
    "invalid_candidate",
    [
        "missing_tag",
        "duplicate_tag",
        "missing_revision",
        "empty_revision",
        "invalid_url",
        "missing_url",
    ],
)
def test_rollout_rejects_invalid_tag_without_promoting_a_candidate(
    tmp_path: Path,
    invalid_candidate: str,
) -> None:
    """Invalid tag metadata must restore existing traffic, not promote latest."""
    log = tmp_path / "calls.log"
    deployed = tmp_path / "deployed"
    sha = _rollout_env(tmp_path)["COMMIT_SHA"]
    candidate = {
        "tag": f"sha-{sha}",
        "revisionName": "farmable-00002",
        "url": "https://candidate.farmable.run.app",
    }
    if invalid_candidate == "missing_tag":
        candidate["tag"] = "some-other-tag"
    elif invalid_candidate == "missing_revision":
        del candidate["revisionName"]
    elif invalid_candidate == "empty_revision":
        candidate["revisionName"] = ""
    elif invalid_candidate == "invalid_url":
        candidate["url"] = "http://candidate.farmable.run.app"
    elif invalid_candidate == "missing_url":
        del candidate["url"]
    traffic = [candidate, candidate] if invalid_candidate == "duplicate_tag" else [candidate]
    payload = json.dumps({"status": {"traffic": traffic}})
    _fake_gcloud(
        tmp_path,
        _log_calls(log) + _LIST_STUB + 'if [[ "$*" == *"run deploy"* ]]; then\n'
        f'  touch "{deployed}"; exit 0\n'
        "fi\n"
        'if [[ "$*" == *"latestCreatedRevisionName"* ]]; then\n'
        "  echo 'farmable-unrelated'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"run services describe"* ]]; then\n'
        f'  if [[ ! -f "{deployed}" ]]; then\n'
        '    echo \'{"status":{"traffic":[{"revisionName":"farmable-00001","percent":100}]}}\'\n'
        "  else\n"
        "    cat <<'FAKEJSON'\n" + payload + "\nFAKEJSON\n"
        "  fi\n"
        "  exit 0\n"
        "fi\n"
        "exit 0\n",
    )
    # A candidate must be rejected before any HTTP checks. Fail fast if reached.
    curl = tmp_path / "curl"
    curl.write_text(
        '#!/usr/bin/env bash\nprintf "unexpected HTTP request\\n" >>"' + str(log) + '"\nexit 1\n',
        encoding="utf-8",
    )
    curl.chmod(0o755)
    sleep = tmp_path / "sleep"
    sleep.write_text("#!/usr/bin/env bash\nexit 0\n", encoding="utf-8")
    sleep.chmod(0o755)
    result = _run("infra/gcp-rollout.sh", _rollout_env(tmp_path))
    calls = log.read_text(encoding="utf-8")
    assert result.returncode != 0
    assert "unexpected HTTP request" not in calls
    traffic_updates = [line for line in calls.splitlines() if "update-traffic" in line]
    assert len(traffic_updates) == 1
    assert "--to-revisions=farmable-00001=100" in traffic_updates[0]
    assert "services delete" not in calls


# A first deploy that fails after the revision exists: the service is absent before
# the run, `gcloud run deploy` succeeds, then resolving the tagged revision's URL
# fails. That reaches rollback() with service_existed=false and cleanup_revision set --
# the state that arms the only irreversible action in the script.
_FAILED_FIRST_DEPLOY_STUB = r"""
if [[ "$*" == *"run services list"* ]]; then exit 0; fi
if [[ "$*" == *"latestCreatedRevisionName"* ]]; then
  printf '%s\n' 'farmable-00002'; exit 0
fi
if [[ "$*" == *"run services describe"* ]]; then
  printf '%s\n' '{"status":{"traffic":[]}}'; exit 0
fi
if [[ "$*" == *"run revisions list"* ]]; then
  printf '%s\n' "${FAKE_REVISIONS:-farmable-00002}"; exit 0
fi
"""


@requires_jq
def test_failed_first_deploy_deletes_only_a_service_this_run_created(
    tmp_path: Path,
) -> None:
    """Positive proof: the service holds exactly one revision and it is the one this
    run deployed. Then deleting it destroys only what this run built.
    """
    log = tmp_path / "calls.log"
    _fake_gcloud(
        tmp_path,
        _log_calls(log) + _FAILED_FIRST_DEPLOY_STUB + "exit 0\n",
    )
    result = _run(
        "infra/gcp-rollout.sh",
        {**_rollout_env(tmp_path), "FAKE_REVISIONS": "farmable-00002"},
    )
    assert result.returncode != 0
    assert "services delete" in log.read_text(encoding="utf-8")


@requires_jq
def test_failed_first_deploy_refuses_to_delete_a_service_holding_other_revisions(
    tmp_path: Path,
) -> None:
    """The dangerous case. `services delete` previously fired on absence of positive
    evidence -- service_existed=false plus a revision name -- so any way the existence
    probe could read a live service as absent (a wrong projection, a filter that
    matches nothing) destroyed a service serving production traffic.

    Revisions this run did not create are proof the probe was wrong. The script must
    refuse and hand over to an operator rather than delete.
    """
    log = tmp_path / "calls.log"
    _fake_gcloud(
        tmp_path,
        _log_calls(log) + _FAILED_FIRST_DEPLOY_STUB + "exit 0\n",
    )
    result = _run(
        "infra/gcp-rollout.sh",
        {
            **_rollout_env(tmp_path),
            "FAKE_REVISIONS": "farmable-00001\nfarmable-00002",
        },
    )
    assert result.returncode != 0
    assert "services delete" not in log.read_text(encoding="utf-8")
    assert "operator action required" in result.stderr


@requires_jq
def test_failed_first_deploy_refuses_to_delete_when_the_revision_probe_fails(
    tmp_path: Path,
) -> None:
    """If the proof itself cannot be obtained, that is not proof. A failing
    `revisions list` must leave the service alone rather than fall through to the
    delete, which is how "absence of evidence" became "evidence of absence" the
    first time.
    """
    log = tmp_path / "calls.log"
    _fake_gcloud(
        tmp_path,
        _log_calls(log) + 'if [[ "$*" == *"run services list"* ]]; then exit 0; fi\n'
        'if [[ "$*" == *"latestCreatedRevisionName"* ]]; then\n'
        "  printf '%s\\n' 'farmable-00002'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"run services describe"* ]]; then\n'
        "  printf '%s\\n' '{\"status\":{\"traffic\":[]}}'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"run revisions list"* ]]; then\n'
        "  echo 'ERROR: HTTPError 503: backend error' >&2; exit 1\n"
        "fi\n"
        "exit 0\n",
    )
    result = _run("infra/gcp-rollout.sh", _rollout_env(tmp_path))
    assert result.returncode != 0
    assert "services delete" not in log.read_text(encoding="utf-8")
    assert "operator action required" in result.stderr


def _provider_secret_gcloud(log: Path, sha: str, *, secrets: str, versions: str) -> str:
    """Successful-path gcloud stub that also answers Secret Manager discovery.

    `secrets list` and `secrets versions list` are matched separately: "secrets list"
    is not a substring of "secrets versions list", so the two cannot be confused.
    """
    service_json = (
        '{"status":{"traffic":[{"tag":"sha-' + sha + '",'
        '"url":"https://sha-' + sha[:8] + '---farmable.run.app",'
        '"revisionName":"farmable-00002"}]},' + _service_spec(REFERENCE_ENV_V1)[1:]
    )
    return (
        _log_calls(log) + 'if [[ "$*" == *"secrets versions list"* ]]; then\n'
        f"  printf '%s\\n' '{versions}'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"secrets list"* ]]; then\n'
        f"  printf '%s\\n' '{secrets}'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"run services list"* ]]; then exit 0; fi\n'
        'if [[ "$*" == *"latestCreatedRevisionName"* ]]; then\n'
        "  printf '%s\\n' 'farmable-00002'; exit 0\n"
        "fi\n"
        'if [[ "$*" == *"run services describe"* ]]; then\n'
        "  cat <<'FAKEJSON'\n" + service_json + "\nFAKEJSON\n"
        "  exit 0\n"
        "fi\n" + _STORAGE_STUB + "exit 0\n"
    )


def _provider_secret_run(tmp_path: Path, log: Path, *, secrets: str, versions: str):
    sha = "0123456789abcdef0123456789abcdef01234567"
    _fake_gcloud(tmp_path, _provider_secret_gcloud(log, sha, secrets=secrets, versions=versions))
    _fake_curl(tmp_path)
    bucket = tmp_path / "bucket"
    bucket.mkdir()
    return _run("infra/gcp-rollout.sh", {**_rollout_env(tmp_path), "FAKE_BUCKET": str(bucket)})


@requires_jq
def test_rollout_runs_integrations_live_so_the_backend_holds_the_provider_keys() -> None:
    """The mobile app is offline-first but must not ship provider keys, so the backend
    calls providers on its behalf. A key extracted from an APK is a key leaked, which
    is why INTEGRATIONS_MODE must not deploy as `disabled`.
    """
    rollout = read("infra/gcp-rollout.sh")
    assert 'INTEGRATIONS_MODE="${INTEGRATIONS_MODE:-live}"' in rollout
    assert "INTEGRATIONS_MODE=disabled" not in rollout


@requires_jq
def test_rollout_wires_a_provider_secret_that_holds_an_enabled_version(tmp_path: Path) -> None:
    log = tmp_path / "calls.log"
    result = _provider_secret_run(
        tmp_path,
        log,
        secrets="farmable-staging-twilio-auth-token",
        versions="projects/1/secrets/farmable-staging-twilio-auth-token/versions/1",
    )
    assert result.returncode == 0, result.stderr + result.stdout
    calls = log.read_text(encoding="utf-8")
    assert "TWILIO_AUTH_TOKEN=farmable-staging-twilio-auth-token:latest" in calls
    assert "INTEGRATIONS_MODE=live" in calls
    assert "Provider secrets wired: TWILIO_AUTH_TOKEN" in result.stdout


@requires_jq
def test_rollout_skips_a_provider_secret_with_no_enabled_version(tmp_path: Path) -> None:
    """Referencing a secret that holds no version makes the container fail to start,
    while omitting it leaves one integration unavailable. Omitting is the safe half of
    that trade, so an empty version list must skip rather than reference.
    """
    log = tmp_path / "calls.log"
    result = _provider_secret_run(
        tmp_path, log, secrets="farmable-staging-twilio-auth-token", versions=""
    )
    assert result.returncode == 0, result.stderr + result.stdout
    calls = log.read_text(encoding="utf-8")
    assert "TWILIO_AUTH_TOKEN" not in calls
    assert "DATABASE_URL=farmable-staging-database-url:latest" in calls
    assert "TWILIO_AUTH_TOKEN" in result.stdout.split("skipped", 1)[1]


@requires_jq
def test_rollout_aborts_when_secret_manager_cannot_be_listed(tmp_path: Path) -> None:
    """A transient listing failure must not read as "no provider secrets exist" and
    deploy a service with none of them wired.
    """
    log = tmp_path / "calls.log"
    _fake_gcloud(
        tmp_path,
        _log_calls(log) + 'if [[ "$*" == *"secrets list"* ]]; then\n'
        "  echo 'ERROR: HTTPError 503: backend error' >&2; exit 1\n"
        "fi\n"
        'if [[ "$*" == *"run services list"* ]]; then exit 0; fi\n'
        "exit 0\n",
    )
    result = _run("infra/gcp-rollout.sh", _rollout_env(tmp_path))
    assert result.returncode != 0
    assert "refusing to deploy" in result.stderr
    assert "run deploy" not in log.read_text(encoding="utf-8")


@requires_jq
def test_secret_smoke_rejects_a_literal_provider_key(tmp_path: Path) -> None:
    """A provider key pasted into a workflow argument instead of Secret Manager is the
    failure this smoke exists to catch, and it must name the variable without echoing
    the value it just found.
    """
    leaked = REFERENCE_ENV_V1 + ',{"name":"TWILIO_AUTH_TOKEN","value":"super-secret-token"}'
    _fake_gcloud(tmp_path, _describe_body(leaked))
    result = _run("infra/gcp-secret-smoke.sh", _secret_env(tmp_path))
    assert result.returncode != 0
    assert "TWILIO_AUTH_TOKEN" in result.stderr
    assert "super-secret-token" not in result.stderr + result.stdout


def test_entrypoint_supervises_the_worker_instead_of_dying_with_it() -> None:
    entrypoint = read("infra/cloudrun-entrypoint.sh")
    # `wait -n "$worker_pid" "$api_pid"` returned on whichever child exited first, and
    # the EXIT trap then killed the other. Only the API's exit may end the container.
    assert 'wait -n "$worker_pid" "$api_pid"' not in entrypoint
    assert 'while kill -0 "$api_pid"' in entrypoint
    assert "start_worker" in entrypoint


def test_entrypoint_keeps_the_api_serving_when_the_worker_keeps_crashing(
    tmp_path: Path,
) -> None:
    """A fault in the background queue must not take the HTTP service down with it: at
    `--max=1` that is total downtime, and the queue currently carries no demo-critical
    work. Stub both children so a crash loop is observable without a real worker.

    Output goes to a file rather than a pipe: on timeout the stubbed `sleep` outlives
    the shell, and a grandchild holding a pipe open can wedge `communicate()`.
    """
    starts = tmp_path / "starts.log"
    for name, body in (
        ("python", f'printf "worker\\n" >>"{starts}"\nexit 1\n'),
        ("uvicorn", f'printf "api\\n" >>"{starts}"\nsleep 6\n'),
    ):
        stub = tmp_path / name
        stub.write_text("#!/usr/bin/env bash\n" + body, encoding="utf-8")
        stub.chmod(0o755)

    output = tmp_path / "output.log"
    with output.open("w", encoding="utf-8") as handle:
        with pytest.raises(subprocess.TimeoutExpired):
            subprocess.run(  # noqa: S603 - fixed shell and repository script
                [_bash(), str(ROOT / "infra/cloudrun-entrypoint.sh")],
                check=False,
                env={**os.environ, "PATH": _path(tmp_path)},
                stdout=handle,
                stderr=handle,
                timeout=5,
            )

    observed = starts.read_text(encoding="utf-8").split()
    # Timing out is the assertion: the script was still running after the worker died.
    assert observed.count("api") == 1
    assert observed.count("worker") > 1
    assert "restarting it and leaving the API serving" in output.read_text(encoding="utf-8")


_REQUIRED_CONFIG_VARS = (
    "GCP_PROJECT_ID",
    "GCP_WORKLOAD_IDENTITY_PROVIDER",
    "GCP_DEPLOYER_SERVICE_ACCOUNT",
    "GCP_RUNTIME_SERVICE_ACCOUNT",
    "GCP_ARTIFACT_REPOSITORY",
    "GCP_CLOUD_SQL_INSTANCE",
    "GCP_CLOUD_SQL_CONNECTION",
    "GCP_MEDIA_BUCKET",
    "GCP_DATABASE_SECRET",
    "GCP_EXPORT_SECRET",
    "GCP_GEMINI_SECRET",
)


def _required_config_env(tmp_path: Path) -> dict:
    """A clean environment: any GCP_* left in the ambient environment would mask
    the very variable a case is trying to leave unset."""
    environment = {name: value for name, value in os.environ.items() if not name.startswith("GCP_")}
    environment["GITHUB_OUTPUT"] = str(tmp_path / "github-output")
    for name in _REQUIRED_CONFIG_VARS:
        environment[name] = f"value-for-{name}"
    return environment


def test_required_config_emits_every_deployment_output(tmp_path: Path) -> None:
    environment = _required_config_env(tmp_path)
    result = _run("infra/gcp-required-config.sh", environment)
    assert result.returncode == 0, result.stderr
    written = (tmp_path / "github-output").read_text(encoding="utf-8").splitlines()
    assert written == [
        "project=value-for-GCP_PROJECT_ID",
        "repository=value-for-GCP_ARTIFACT_REPOSITORY",
        "sql_instance=value-for-GCP_CLOUD_SQL_INSTANCE",
        "sql_connection=value-for-GCP_CLOUD_SQL_CONNECTION",
        "media_bucket=value-for-GCP_MEDIA_BUCKET",
        "runtime_account=value-for-GCP_RUNTIME_SERVICE_ACCOUNT",
        "database_secret=value-for-GCP_DATABASE_SECRET",
        "export_secret=value-for-GCP_EXPORT_SECRET",
        "gemini_secret=value-for-GCP_GEMINI_SECRET",
    ]


@pytest.mark.parametrize("unset", _REQUIRED_CONFIG_VARS)
def test_required_config_names_the_variable_that_is_unset(tmp_path: Path, unset: str) -> None:
    """A chained `test -n` exits 1 saying nothing about which of ten protected
    variables an operator has not set. GCP_CLOUD_SQL_INSTANCE was not checked at
    all, so it failed in the backup step -- after an image was built and pushed.
    """
    environment = _required_config_env(tmp_path)
    environment[unset] = ""
    result = _run("infra/gcp-required-config.sh", environment)
    assert result.returncode != 0
    assert unset in result.stderr
    assert not (tmp_path / "github-output").exists()


def test_required_config_runs_before_authentication_and_feeds_the_backup() -> None:
    """GCP_CLOUD_SQL_INSTANCE reached gcp-backup.sh straight from `vars`, unchecked,
    so an operator who had not set it lost a build and push before finding out. The
    check now runs first, ahead of the Google Cloud auth step, and the backup step
    consumes the validated output instead of the raw variable.
    """
    workflow = read(".github/workflows/deploy-staging.yml")
    assert "bash infra/gcp-required-config.sh" in workflow
    assert workflow.index("infra/gcp-required-config.sh") < workflow.index(
        "google-github-actions/auth@"
    )
    assert "GCP_CLOUD_SQL_INSTANCE: ${{ vars.GCP_CLOUD_SQL_INSTANCE }}" in workflow
    assert "CLOUD_SQL_INSTANCE: ${{ steps.config.outputs.sql_instance }}" in workflow
    assert 'test -n "$PROJECT"' not in workflow
    for name in _REQUIRED_CONFIG_VARS:
        assert name in read("infra/gcp-required-config.sh"), name


# `${VAR-default}`, not `${VAR:-default}`: a case that sets a fake value to the
# empty string must remain a failing state rather than falling back to a default.
_VERIFY_SETUP_STUB = r"""
case "$*" in
  *"services list"*)
    printf '%s\n' "${FAKE_ENABLED_API-run.googleapis.com}" ;;
  *"buckets describe"*)
    case "$*" in
      *public_access_prevention*) printf '%s\n' "${FAKE_PREVENTION-enforced}" ;;
      *uniform_bucket_level_access*) printf '%s\n' "${FAKE_UNIFORM-True}" ;;
    esac ;;
  *"secrets versions describe latest"*)
    printf '%s\n' "${FAKE_SECRET_STATE-ENABLED}" ;;
  *"providers describe"*)
    default_condition="assertion.repository == 'ctrl-alt-elite-za/Farmable' && "
    default_condition+="assertion.ref == 'refs/heads/main'"
    printf '%s\n' "${FAKE_CONDITION-$default_condition}" ;;
esac
exit 0
"""


def _verify_setup_env(tmp_path: Path) -> dict:
    return {
        **os.environ,
        "PATH": _path(tmp_path),
        "GCP_PROJECT": "farmable-project",
        "GCS_BUCKET": "farmable-project-farmable-staging-media",
    }


def test_verify_setup_passes_when_the_live_project_matches_the_contract(
    tmp_path: Path,
) -> None:
    _fake_gcloud(tmp_path, _VERIFY_SETUP_STUB)
    result = _run("infra/gcp-verify-setup.sh", _verify_setup_env(tmp_path))
    assert result.returncode == 0, result.stderr
    assert "PASS: API enabled: run.googleapis.com" in result.stdout
    assert "PASS: Media bucket blocks public access" in result.stdout
    assert "FAIL" not in result.stdout + result.stderr


def test_verify_setup_reports_every_unmet_check_not_only_the_first(tmp_path: Path) -> None:
    """Terraform creates empty Secret Manager containers, so a disabled ``latest``
    version is a likely first-deploy failure and must be named, not hidden behind
    an earlier failing check. One run has to produce the operator's whole to-do list.
    """
    _fake_gcloud(tmp_path, _VERIFY_SETUP_STUB)
    environment = {
        **_verify_setup_env(tmp_path),
        "FAKE_PREVENTION": "inherited",
        "FAKE_SECRET_STATE": "DISABLED",
        "FAKE_CONDITION": (
            "assertion.repository == 'someone-else/Fork' && " "assertion.ref == 'refs/heads/main'"
        ),
    }
    result = _run("infra/gcp-verify-setup.sh", environment)
    assert result.returncode != 0
    assert "FAIL: Media bucket public access prevention is 'inherited'" in result.stderr
    assert (
        "FAIL: Secret latest version is 'DISABLED', expected 'ENABLED': "
        "farmable-staging-database-url" in result.stderr
    )
    assert (
        "FAIL: Secret latest version is 'DISABLED', expected 'ENABLED': "
        "farmable-staging-gemini-api-key" in result.stderr
    )
    assert "ctrl-alt-elite-za/Farmable" in result.stderr
    assert "4 Google Cloud setup check(s) failed" in result.stderr
    assert "PASS: Media bucket uses uniform bucket-level access" in result.stdout


@pytest.mark.parametrize(
    "condition",
    [
        "assertion.repository == 'ctrl-alt-elite-za/Farmable' || true",
        (
            "assertion.repository == 'ctrl-alt-elite-za/Farmable-other' && "
            "assertion.ref == 'refs/heads/main'"
        ),
        "assertion.repository == 'ctrl-alt-elite-za/Farmable'",
    ],
)
def test_verify_setup_rejects_unsafe_workload_identity_conditions(
    tmp_path: Path, condition: str
) -> None:
    _fake_gcloud(tmp_path, _VERIFY_SETUP_STUB)
    environment = {**_verify_setup_env(tmp_path), "FAKE_CONDITION": condition}
    result = _run("infra/gcp-verify-setup.sh", environment)
    assert result.returncode != 0
    assert "Workload identity provider is not pinned" in result.stderr


def test_verify_setup_checks_the_deployment_secret_latest_version(
    tmp_path: Path,
) -> None:
    _fake_gcloud(tmp_path, _VERIFY_SETUP_STUB)
    environment = {**_verify_setup_env(tmp_path), "FAKE_SECRET_STATE": "DISABLED"}
    result = _run("infra/gcp-verify-setup.sh", environment)
    assert result.returncode != 0
    assert "Secret latest version is 'DISABLED'" in result.stderr


def test_verify_setup_accepts_an_enabled_latest_version(tmp_path: Path) -> None:
    _fake_gcloud(tmp_path, _VERIFY_SETUP_STUB)
    result = _run("infra/gcp-verify-setup.sh", _verify_setup_env(tmp_path))
    assert result.returncode == 0, result.stderr
    assert "PASS: Secret latest version is enabled: farmable-staging-database-url" in result.stdout


def test_operator_acceptance_evidence_is_documented() -> None:
    """The repository work for issue #6 is merged; what is left is live evidence an
    operator gathers by hand. Naming each piece, next to the command that produces
    it, is what stops "deployed" from meaning only "the workflow went green".
    """
    doc = read("docs/deploy-staging-acceptance.md")
    for marker in (
        "africa-south1",
        "infra/gcp-verify-setup.sh",
        "infra/gcp-required-config.sh",
        "DEPLOY_FREEZE",
        "gcloud sql backups list",
        "alembic current",
        "gcloud run revisions list",
        ".github/workflows/nightly-staging.yml",
        "budget",
        "PostGIS",
        "rollback",
        "Workload Identity Federation",
    ):
        assert marker in doc, marker
    # Issue #6's body still describes a Cape Town EC2 deployment that was never
    # built. The operator checklist must not reintroduce it.
    lowered = doc.lower()
    for stale in ("af-south-1", "aws", "ec2"):
        assert stale not in lowered, stale
