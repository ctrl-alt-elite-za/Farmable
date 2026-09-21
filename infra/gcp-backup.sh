#!/usr/bin/env bash
set -Eeuo pipefail

: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${CLOUD_SQL_INSTANCE:?CLOUD_SQL_INSTANCE is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"

# --async lets us verify the Cloud SQL operation, rather than treating command
# submission as a completed backup. No database credentials are read by this
# script or placed in workflow output.
operation="$(gcloud sql backups create \
  --project="$GCP_PROJECT" \
  --instance="$CLOUD_SQL_INSTANCE" \
  --description="farmable-${COMMIT_SHA}" \
  --async \
  --format='value(name)')"

if [[ -z "$operation" || ! "$operation" =~ ^[A-Za-z0-9._-]+$ ]]; then
  echo "Cloud SQL did not return a valid backup operation id" >&2
  exit 1
fi

# `gcloud sql operations wait|describe` take the operation name plus wide flags
# only -- the synopsis is `gcloud sql operations wait OPERATION [OPERATION ...]
# [--timeout=TIMEOUT]`. Passing --instance is an unrecognised argument, which under
# `set -Eeuo pipefail` fails the backup step and so every deploy, before migration.
gcloud sql operations wait "$operation" \
  --project="$GCP_PROJECT" \
  --quiet >/dev/null

status="$(gcloud sql operations describe "$operation" \
  --project="$GCP_PROJECT" \
  --format='value(status)')"
error_code="$(gcloud sql operations describe "$operation" \
  --project="$GCP_PROJECT" \
  --format='value(error.errors[0].code)')"

if [[ "$status" != "DONE" || -n "$error_code" ]]; then
  echo "Cloud SQL backup operation did not complete successfully" >&2
  exit 1
fi

echo "Cloud SQL backup completed before migration"
