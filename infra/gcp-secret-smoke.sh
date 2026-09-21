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
# `gcloud run services describe --format=json` may emit the Knative v1 encoding
# (valueFrom/secretKeyRef.name/.key) or the Admin v2 one
# (valueSource/secretKeyRef.secret/.version). The assertion being made -- that these
# env vars are Secret Manager references rather than literals -- is true in both, so
# accept either rather than staking a deploy-blocking check on one shape.
for name in DATABASE_URL GEMINI_API_KEY; do
  if ! jq -e --arg name "$name" '
    any(.. | objects;
      .name == $name and (
        (.valueFrom.secretKeyRef.name != null and .valueFrom.secretKeyRef.key == "latest")
        or
        (.valueSource.secretKeyRef.secret != null and .valueSource.secretKeyRef.version == "latest")
      ))
  ' <<<"$service_json" >/dev/null; then
    # Name the variable only. The service JSON is never printed: if the value were a
    # literal, echoing it here would turn this assertion into a log exfiltration.
    echo "$name is not a Secret Manager reference on the Cloud Run service" >&2
    exit 1
  fi
done
echo "Cloud Run Secret Manager references are configured"
