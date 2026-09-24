#!/usr/bin/env bash
set -Eeuo pipefail

# Every protected `staging` variable the deploy workflow needs, checked in one
# place. The workflow runs this before authenticating, so a name that was never
# set is reported as itself rather than as an opaque auth failure -- or, for
# GCP_CLOUD_SQL_INSTANCE, which nothing checked until the backup step, after an
# image had already been built and pushed.
: "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"

required=(
  GCP_PROJECT_ID
  GCP_WORKLOAD_IDENTITY_PROVIDER
  GCP_DEPLOYER_SERVICE_ACCOUNT
  GCP_RUNTIME_SERVICE_ACCOUNT
  GCP_ARTIFACT_REPOSITORY
  GCP_CLOUD_SQL_INSTANCE
  GCP_CLOUD_SQL_CONNECTION
  GCP_MEDIA_BUCKET
  GCP_DATABASE_SECRET
  GCP_GEMINI_SECRET
)

missing=()
for name in "${required[@]}"; do
  if [[ -z "${!name:-}" ]]; then
    missing+=("$name")
  fi
done

if [[ ${#missing[@]} -gt 0 ]]; then
  # Names only. These hold non-secret resource identifiers, but never echoing a
  # value means a secret pasted into the wrong variable cannot reach the log here.
  echo "Missing required staging variables: ${missing[*]}" >&2
  echo "See infra/README.md 'One-time operator setup' step 4." >&2
  exit 1
fi

{
  printf 'project=%s\n' "$GCP_PROJECT_ID"
  printf 'repository=%s\n' "$GCP_ARTIFACT_REPOSITORY"
  printf 'sql_instance=%s\n' "$GCP_CLOUD_SQL_INSTANCE"
  printf 'sql_connection=%s\n' "$GCP_CLOUD_SQL_CONNECTION"
  printf 'media_bucket=%s\n' "$GCP_MEDIA_BUCKET"
  printf 'runtime_account=%s\n' "$GCP_RUNTIME_SERVICE_ACCOUNT"
  printf 'database_secret=%s\n' "$GCP_DATABASE_SECRET"
  printf 'gemini_secret=%s\n' "$GCP_GEMINI_SECRET"
} >>"$GITHUB_OUTPUT"

echo "All required staging deployment variables are set"
