#!/usr/bin/env bash
set -Eeuo pipefail

: "${GCS_BUCKET:?GCS_BUCKET is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"

object="gs://${GCS_BUCKET}/deployment-smoke/${COMMIT_SHA}.txt"
expected="farmable storage smoke ${COMMIT_SHA}"
local_file="$(mktemp)"
downloaded="$(mktemp)"
trap 'rm -f "$local_file" "$downloaded"' EXIT
printf '%s\n' "$expected" >"$local_file"

# The bucket is configured with public access prevention. These operations use
# the federated deployment identity and prove private upload plus download.
gcloud storage cp "$local_file" "$object" --quiet >/dev/null
gcloud storage cp "$object" "$downloaded" --quiet >/dev/null
diff -u "$local_file" "$downloaded" >/dev/null
gcloud storage rm "$object" --quiet >/dev/null
echo "Private Cloud Storage upload/download smoke passed"
