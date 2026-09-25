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
for name in DATABASE_URL EXPORT_TOKEN_SECRET GEMINI_API_KEY; do
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

# The rollout wires provider credentials only when a secret holds an enabled version,
# so these are absent rather than required. Absent is fine; present as a literal is not
# -- that would mean a key was pasted into a workflow argument instead of Secret
# Manager, which is exactly what the no-plaintext rule exists to prevent.
for name in TWILIO_AUTH_TOKEN TURNSTILE_SECRET AZURE_SPEECH_KEY CROP_HEALTH_API_KEY \
  MAPS_SERVER_API_KEY TWILIO_ACCOUNT_SID TWILIO_VERIFY_SERVICE_SID TURNSTILE_HOSTNAME \
  TURNSTILE_SITE_KEY AZURE_SPEECH_RESOURCE AZURE_SPEECH_REGION GEMINI_MODEL; do
  if jq -e --arg name "$name" '
    any(.. | objects; .name == $name and has("value"))
  ' <<<"$service_json" >/dev/null; then
    echo "$name is set as a literal value; it must be a Secret Manager reference" >&2
    exit 1
  fi
done
echo "Cloud Run Secret Manager references are configured"
