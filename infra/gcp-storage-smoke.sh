#!/usr/bin/env bash
set -Eeuo pipefail

: "${GCS_BUCKET:?GCS_BUCKET is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"

object="gs://${GCS_BUCKET}/deployment-smoke/${COMMIT_SHA}.txt"
expected="farmable storage smoke ${COMMIT_SHA}"
local_file="$(mktemp)"
downloaded="$(mktemp)"
uploaded=false
cleanup() {
  rm -f "$local_file" "$downloaded"
  if [[ "$uploaded" == true ]]; then
    gcloud storage rm "$object" --quiet >/dev/null 2>&1 || true
  fi
}
trap cleanup EXIT
printf '%s\n' "$expected" >"$local_file"

# The bucket is configured with public access prevention. These operations use
# the federated deployment identity and prove private upload plus download.
uploaded=true
gcloud storage cp "$local_file" "$object" --quiet >/dev/null
gcloud storage cp "$object" "$downloaded" --quiet >/dev/null
diff -u "$local_file" "$downloaded" >/dev/null
gcloud storage rm "$object" --quiet >/dev/null
uploaded=false
echo "Private Cloud Storage upload/download smoke passed"
