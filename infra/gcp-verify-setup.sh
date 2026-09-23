#!/usr/bin/env bash
set -Eeuo pipefail

# Operator preflight for the Johannesburg demo deployment. Run it once, signed in
# with gcloud, after `terraform apply` and after the secret versions exist --
# before the first push to `main`.
#
# It reads configuration only: nothing is created, changed or deleted, and no
# secret payload is ever fetched, so it is safe to run against the live project.
# Every check is reported, rather than stopping at the first failure, because the
# point is one list of what the operator still has to do.
: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${GCS_BUCKET:?GCS_BUCKET is required}"
GCP_REGION="${GCP_REGION:-africa-south1}"
SECRET_PREFIX="${SECRET_PREFIX:-farmable-staging}"
WORKLOAD_IDENTITY_POOL="${WORKLOAD_IDENTITY_POOL:-farmable-staging-github}"
WORKLOAD_IDENTITY_PROVIDER_ID="${WORKLOAD_IDENTITY_PROVIDER_ID:-github}"
EXPECTED_REPOSITORY="${EXPECTED_REPOSITORY:-ctrl-alt-elite-za/Farmable}"

if ! command -v gcloud >/dev/null 2>&1; then
  echo "gcloud is required; install the Google Cloud CLI and authenticate" >&2
  exit 1
fi

failures=0

pass() {
  echo "PASS: $1"
}

fail() {
  echo "FAIL: $1" >&2
  failures=$((failures + 1))
}

required_apis=(
  artifactregistry.googleapis.com
  iamcredentials.googleapis.com
  run.googleapis.com
  secretmanager.googleapis.com
  sqladmin.googleapis.com
  sts.googleapis.com
  storage.googleapis.com
)
for api in "${required_apis[@]}"; do
  # A command substitution inside [[ ]] cannot trip errexit, so a project the
  # caller cannot read reports as "not enabled" rather than aborting the report.
  if [[ -n "$(gcloud services list --enabled --project="$GCP_PROJECT" \
    --filter="config.name=${api}" --format='value(config.name)' 2>/dev/null)" ]]; then
    pass "API enabled: ${api}"
  else
    fail "API not enabled: ${api}"
  fi
done

prevention="$(gcloud storage buckets describe "gs://${GCS_BUCKET}" \
  --format='value(public_access_prevention)' 2>/dev/null || true)"
if [[ "$prevention" == "enforced" ]]; then
  pass "Media bucket blocks public access"
else
  fail "Media bucket public access prevention is '${prevention}', expected 'enforced'"
fi

uniform="$(gcloud storage buckets describe "gs://${GCS_BUCKET}" \
  --format='value(uniform_bucket_level_access)' 2>/dev/null || true)"
if [[ "$uniform" == "True" || "$uniform" == "true" ]]; then
  pass "Media bucket uses uniform bucket-level access"
else
  fail "Media bucket uniform bucket-level access is '${uniform}', expected enabled"
fi

# Terraform creates empty Secret Manager containers and never receives a value, so
# a container with no enabled version is the likeliest first-deploy failure. Only
# version names and states are read here.
required_secrets=(
  "${SECRET_PREFIX}-database-url"
  "${SECRET_PREFIX}-gemini-api-key"
)
for secret in "${required_secrets[@]}"; do
  if [[ -n "$(gcloud secrets versions list "$secret" --project="$GCP_PROJECT" \
    --filter='state=enabled' --format='value(name)' --limit=1 2>/dev/null)" ]]; then
    pass "Secret has an enabled version: ${secret}"
  else
    fail "Secret has no enabled version: ${secret}"
  fi
done

condition="$(gcloud iam workload-identity-pools providers describe \
  "$WORKLOAD_IDENTITY_PROVIDER_ID" --project="$GCP_PROJECT" --location=global \
  --workload-identity-pool="$WORKLOAD_IDENTITY_POOL" \
  --format='value(attributeCondition)' 2>/dev/null || true)"
if [[ "$condition" == *"$EXPECTED_REPOSITORY"* ]]; then
  pass "Workload identity provider is pinned to ${EXPECTED_REPOSITORY}"
else
  fail "Workload identity provider is not pinned to ${EXPECTED_REPOSITORY}"
fi

if [[ "$failures" -gt 0 ]]; then
  echo "${failures} Google Cloud setup check(s) failed; see infra/README.md" >&2
  exit 1
fi
echo "Google Cloud demo setup checks passed in ${GCP_REGION}"
