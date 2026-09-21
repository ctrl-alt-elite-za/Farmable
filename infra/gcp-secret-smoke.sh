#!/usr/bin/env bash
set -Eeuo pipefail

: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE is required}"
: "${GCP_REGION:?GCP_REGION is required}"

service_json="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" \
  --region="$GCP_REGION" \
  --format=json)"

# Check only secret reference names. Never print the service JSON: it may contain
# non-secret configuration and this assertion must not turn into a log exfiltration.
for name in DATABASE_URL GEMINI_API_KEY; do
  jq -e --arg name "$name" '
    any(.. | objects;
      .name == $name and .valueSource.secretKeyRef.secret != null and
      .valueSource.secretKeyRef.version == "latest")
  ' <<<"$service_json" >/dev/null
done
echo "Cloud Run Secret Manager references are configured"
