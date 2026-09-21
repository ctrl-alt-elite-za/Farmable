#!/usr/bin/env bash
set -Eeuo pipefail

: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE is required}"
: "${GCP_REGION:?GCP_REGION is required}"

service_json="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" \
  --region="$GCP_REGION" \
  --format=json)"

# `gcloud run services describe` issues a RunNamespacesServicesGetRequest, i.e. the
# Knative v1 API (SERVERLESS_API_VERSION = 'v1'), where a secret-backed env var is
# EnvVar.valueFrom -> EnvVarSource.secretKeyRef -> SecretKeySelector{name, key}.
# Checking that one shape fails loudly if the encoding ever changes; accepting several
# shapes could only fail open.
for name in DATABASE_URL GEMINI_API_KEY; do
  if ! jq -e --arg name "$name" '
    any(.. | objects;
      .name == $name
      and .valueFrom.secretKeyRef.name != null
      and .valueFrom.secretKeyRef.key == "latest")
  ' <<<"$service_json" >/dev/null; then
    # Name the variable only, never the value. If it were a literal, echoing it here
    # would turn this assertion into a log exfiltration.
    echo "$name is not a Secret Manager reference on the Cloud Run service" >&2
    exit 1
  fi
done
echo "Cloud Run Secret Manager references are configured"
