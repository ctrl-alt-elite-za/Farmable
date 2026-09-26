#!/usr/bin/env bash
set -Eeuo pipefail

: "${GCP_PROJECT:?GCP_PROJECT is required}"
: "${GCP_REGION:?GCP_REGION is required}"
: "${CLOUD_RUN_SERVICE:?CLOUD_RUN_SERVICE is required}"
: "${IMAGE:?IMAGE is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"
: "${CLOUD_SQL_CONNECTION:?CLOUD_SQL_CONNECTION is required}"
: "${RUNTIME_SERVICE_ACCOUNT:?RUNTIME_SERVICE_ACCOUNT is required}"
: "${DATABASE_SECRET:?DATABASE_SECRET is required}"
: "${EXPORT_SECRET:?EXPORT_SECRET is required}"
: "${GEMINI_SECRET:?GEMINI_SECRET is required}"
: "${GCS_BUCKET:?GCS_BUCKET is required}"
FORECAST_DATA_MODE="${FORECAST_DATA_MODE:-disabled}"
case "$FORECAST_DATA_MODE" in disabled|sample|historical) ;; *)
  echo 'Invalid forecast data mode' >&2; exit 1 ;;
esac

# `describe` exits non-zero both when the service is absent and when the call simply
# failed, and the two are distinguishable only by parsing human-readable error text.
# `list --filter` answers the existence question directly: absent is empty output with
# a zero exit, so a transient 503 or a permissions problem stays a failure instead of
# reading as "absent" and arming the first-deploy `services delete` branch below.
# `run services list` issues a RunNamespacesServicesListRequest -- the Knative v1 API,
# which always populates metadata.name -- so one field is the whole answer.
# $(...) captures stdout only; gcloud's stderr already reaches the workflow log.
if ! existing="$(gcloud run services list \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --filter="metadata.name=${CLOUD_RUN_SERVICE}" \
  --format='value(metadata.name)')"; then
  echo "Could not determine whether ${CLOUD_RUN_SERVICE} exists; refusing to deploy" >&2
  exit 1
fi

if [[ -n "$existing" ]]; then
  service_json="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
    --project="$GCP_PROJECT" --region="$GCP_REGION" --format=json)"
  service_existed=true
  previous_revision="$(jq -r '
    [.status.traffic[]? | select(.percent == 100 and .revisionName != null)] |
    .[0].revisionName // empty
  ' <<<"$service_json")"
  if [[ -z "$previous_revision" ]]; then
    echo "Existing service must route 100% traffic to one revision before deployment" >&2
    exit 1
  fi
else
  service_existed=false
  previous_revision=""
fi
cleanup_revision=""

# Cloud Run only accepts --no-traffic when the service already exists. A new
# service must receive its first revision's default traffic during creation;
# the explicit promotion below still makes the final routing decision.
deploy_traffic_args=()
if [[ "$service_existed" == true ]]; then
  deploy_traffic_args+=(--no-traffic)
fi

rollback() {
  status=$?
  trap - ERR
  echo "Deployment failed; restoring previous Cloud Run traffic" >&2
  if [[ -n "$previous_revision" ]]; then
    gcloud run services update-traffic "$CLOUD_RUN_SERVICE" \
      --project="$GCP_PROJECT" --region="$GCP_REGION" \
      --to-revisions="${previous_revision}=100" --quiet >/dev/null || \
      echo "Cloud Run traffic rollback failed; operator action required" >&2
  elif [[ "$service_existed" == false && -n "$cleanup_revision" ]]; then
    # A first Cloud Run deployment has no older revision that can receive traffic, and
    # the failed one stays reachable at its sha- tag URL, so the service is removed.
    #
    # Deletion is the only irreversible action in this script, and service_existed is
    # the absence of positive evidence: any way the existence probe could read a live
    # service as absent -- a wrong projection, a filter matching nothing -- would point
    # this at a service serving production traffic. So require positive proof instead:
    # a service this run created holds exactly the one revision this run deployed.
    # Revisions we did not create mean the probe was wrong; stop and hand over.
    revisions="$(gcloud run revisions list --service="$CLOUD_RUN_SERVICE" \
      --project="$GCP_PROJECT" --region="$GCP_REGION" \
      --format='value(metadata.name)' 2>/dev/null)" || revisions="__probe_failed__"
    mapfile -t revision_names < <(grep -v '^[[:space:]]*$' <<<"$revisions" || true)
    if [[ ${#revision_names[@]} -eq 1 && "${revision_names[0]}" == "$cleanup_revision" ]]; then
      gcloud run services delete "$CLOUD_RUN_SERVICE" \
        --project="$GCP_PROJECT" --region="$GCP_REGION" --quiet >/dev/null || \
        echo "Failed first deployment could not be removed; operator action required" >&2
    else
      echo "Refusing to delete ${CLOUD_RUN_SERVICE}: it holds revisions this run did" \
        "not create, so it was not created by this run; operator action required" >&2
    fi
  fi
  exit "$status"
}
trap rollback ERR

# Provider credentials are read by the backend, not the mobile app, so every key the
# app needs must reach this container from Secret Manager.
#
# Only wire a secret that actually holds an ENABLED version. Referencing a secret with
# no version makes the Cloud Run container fail to start outright, whereas a provider
# key that is simply absent is a degraded integration: ServiceSettings leaves the field
# None and that one adapter reports the provider unavailable. So skipping beats
# referencing, and the team can add keys incrementally instead of needing all of them
# before the first deploy.
INTEGRATIONS_MODE="${INTEGRATIONS_MODE:-live}"
# Terraform names every secret "${name_prefix}-<id>", so the prefix is recoverable from
# the database secret rather than needing a separate repository variable to drift.
SECRET_PREFIX="${SECRET_PREFIX:-${DATABASE_SECRET%-database-url}}"

# ENV_VAR:secret-id-suffix. DATABASE_URL and GEMINI_API_KEY are wired unconditionally
# from their own variables; the demo cannot run without the first and does not run
# without the second. The rest are optional.
optional_secrets=(
  "GEMINI_MODEL:gemini-model"
  "TWILIO_ACCOUNT_SID:twilio-account-sid"
  "TWILIO_VERIFY_SERVICE_SID:twilio-verify-service-sid"
  "TWILIO_AUTH_TOKEN:twilio-auth-token"
  "TURNSTILE_SECRET:turnstile-secret"
  "TURNSTILE_HOSTNAME:turnstile-hostname"
  "TURNSTILE_SITE_KEY:turnstile-site-key"
  "AZURE_SPEECH_KEY:azure-speech-key"
  "AZURE_SPEECH_RESOURCE:azure-speech-resource"
  "AZURE_SPEECH_REGION:azure-speech-region"
  "CROP_HEALTH_API_KEY:crop-health-api-key"
  "MAPS_SERVER_API_KEY:maps-server-api-key"
  "INFOBIP_BASE_URL:infobip-base-url"
  "INFOBIP_API_KEY:infobip-api-key"
  "INFOBIP_SMS_SENDER:infobip-sms-sender"
  "SMTP_HOST:smtp-host"
  "SMTP_USER:smtp-user"
  "SMTP_PASSWORD:smtp-password"
  "EMAIL_FROM_NAME:email-from-name"
  "EMAIL_FROM_ADDRESS:email-from-address"
)
# Live mode delivers sign-up codes through these; without them sign-up cannot
# complete (and a live backend refuses to boot without its SMTP settings).
otp_delivery_secrets=(INFOBIP_BASE_URL INFOBIP_API_KEY INFOBIP_SMS_SENDER SMTP_HOST SMTP_USER
  SMTP_PASSWORD EMAIL_FROM_NAME EMAIL_FROM_ADDRESS)

# One listing call decides existence for every candidate. Probing each secret
# individually cannot tell NOT_FOUND from a transient 503, and reading a transient
# failure as "absent" would quietly deploy a service with no provider keys at all.
if ! available="$(gcloud secrets list --project="$GCP_PROJECT" \
  --format='value(name.basename())')"; then
  echo "Could not list Secret Manager secrets; refusing to deploy" >&2
  exit 1
fi

export_secret_id="$EXPORT_SECRET"
if ! grep -qxF "$export_secret_id" <<<"$available"; then
  echo "Required export-token secret is missing: $export_secret_id" >&2
  exit 1
fi
export_secret_version="$(gcloud secrets versions list "$export_secret_id" --project="$GCP_PROJECT" \
  --filter='state:ENABLED' --limit=1 --format='value(name)')"
[[ -n "$export_secret_version" ]] || { echo "Required export-token secret has no enabled version" >&2; exit 1; }
secret_args="DATABASE_URL=${DATABASE_SECRET}:latest,GEMINI_API_KEY=${GEMINI_SECRET}:latest,EXPORT_TOKEN_SECRET=${export_secret_id}:latest"
wired=()
skipped=()
for entry in "${optional_secrets[@]}"; do
  env_name="${entry%%:*}"
  secret_id="${SECRET_PREFIX}-${entry#*:}"
  if ! grep -qxF "$secret_id" <<<"$available"; then
    skipped+=("$env_name")
    continue
  fi
  # The secret exists, so a failing version query is a real error, not absence. Left
  # unguarded on purpose: the ERR trap turns it into a fail-closed deploy.
  versions="$(gcloud secrets versions list "$secret_id" --project="$GCP_PROJECT" \
    --filter='state:ENABLED' --limit=1 --format='value(name)')"
  if [[ -n "$versions" ]]; then
    secret_args+=",${env_name}=${secret_id}:latest"
    wired+=("$env_name")
  else
    skipped+=("$env_name")
  fi
done
# Names only, never values: this log is world-readable to anyone with repository access.
echo "Integrations mode: ${INTEGRATIONS_MODE}"
echo "Provider secrets wired: ${wired[*]:-none}"
echo "Provider secrets skipped, no enabled version: ${skipped[*]:-none}"
if [[ "$INTEGRATIONS_MODE" == live ]]; then
  missing_otp=()
  for env_name in "${otp_delivery_secrets[@]}"; do
    [[ " ${wired[*]:-} " == *" ${env_name} "* ]] || missing_otp+=("$env_name")
  done
  if [[ ${#missing_otp[@]} -gt 0 ]]; then
    echo "::warning::Live sign-up OTP delivery is not configured; missing: ${missing_otp[*]}"
  fi
fi

gcloud run deploy "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --image="$IMAGE" --platform=managed "${deploy_traffic_args[@]}" --tag="sha-${COMMIT_SHA}" \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" \
  --add-cloudsql-instances="$CLOUD_SQL_CONNECTION" \
  --set-env-vars="COMMIT_SHA=$COMMIT_SHA,ENVIRONMENT=staging,INTEGRATIONS_MODE=${INTEGRATIONS_MODE},FORECAST_DATA_MODE=$FORECAST_DATA_MODE,TRUSTED_PROXY_HOPS=1" \
  --set-secrets="$secret_args" \
  --command=/app/cloudrun-entrypoint.sh --port=8000 --min=1 --max=1 \
  --cpu=1 --memory=512Mi --no-cpu-throttling --allow-unauthenticated --quiet >/dev/null

# Preserve the existing first-deployment cleanup fallback. This service-wide
# pointer must never select the revision promoted to production traffic.
cleanup_revision="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --format='value(status.latestCreatedRevisionName)')"
[[ -n "$cleanup_revision" ]]
service_json="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" --format=json)"
# Resolve the URL and revision together: another deployment can advance
# latestCreatedRevisionName while our commit tag still points at our candidate.
if ! candidate="$(jq -ce --arg tag "sha-${COMMIT_SHA}" '
  [.status.traffic[]? | select(.tag == $tag)] |
  select(length == 1) | .[0] |
  select(.revisionName | strings | length > 0) |
  select(.url | strings | test("^https://[^/[:space:]]+(/[^[:space:]]*)?$"))
' <<<"$service_json")"; then
  echo "Expected exactly one commit-tagged revision with a name and HTTPS URL" >&2
  false # Trigger the existing ERR rollback, including first-deployment cleanup.
fi
new_revision="$(jq -r '.revisionName' <<<"$candidate")"
revision_url="$(jq -r '.url' <<<"$candidate")"
cleanup_revision="$new_revision"

ready=false
for _ in {1..36}; do
  response="$(curl --fail --silent --show-error --max-time 10 "$revision_url/health/ready" 2>/dev/null || true)"
  if [[ "$(jq -r '.sha // empty' <<<"$response" 2>/dev/null || true)" == "$COMMIT_SHA" ]] &&
    jq -e '.database == "ok" and .worker == "ok"' <<<"$response" >/dev/null 2>&1; then
    ready=true
    break
  fi
  sleep 5
done
[[ "$ready" == true ]]

API_URL="$revision_url" COMMIT_SHA="$COMMIT_SHA" bash infra/gcp-demo-smoke.sh
GCP_PROJECT="$GCP_PROJECT" CLOUD_RUN_SERVICE="$CLOUD_RUN_SERVICE" GCP_REGION="$GCP_REGION" \
  bash infra/gcp-secret-smoke.sh
GCS_BUCKET="$GCS_BUCKET" COMMIT_SHA="$COMMIT_SHA" bash infra/gcp-storage-smoke.sh

gcloud run services update-traffic "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --to-revisions="${new_revision}=100" --quiet >/dev/null
trap - ERR
echo "Cloud Run deployed ${COMMIT_SHA} in ${GCP_REGION}"
