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

gcloud sql operations wait "$operation" \
  --project="$GCP_PROJECT" \
  --instance="$CLOUD_SQL_INSTANCE" \
  --quiet >/dev/null

status="$(gcloud sql operations describe "$operation" \
  --project="$GCP_PROJECT" \
  --instance="$CLOUD_SQL_INSTANCE" \
  --format='value(status)')"
error_code="$(gcloud sql operations describe "$operation" \
  --project="$GCP_PROJECT" \
  --instance="$CLOUD_SQL_INSTANCE" \
  --format='value(error.errors[0].code)')"

if [[ "$status" != "DONE" || -n "$error_code" ]]; then
  echo "Cloud SQL backup operation did not complete successfully" >&2
  exit 1
fi

echo "Cloud SQL backup completed before migration"
