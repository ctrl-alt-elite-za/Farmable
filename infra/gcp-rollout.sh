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
: "${GEMINI_SECRET:?GEMINI_SECRET is required}"
: "${GCS_BUCKET:?GCS_BUCKET is required}"

# `describe` exits non-zero both when the service is absent and when the call simply
# failed, and the two are distinguishable only by parsing human-readable error text.
# `list --filter` answers the existence question directly: absent is empty output with
# a zero exit, so a transient 503 or a permissions problem stays a failure instead of
# reading as "absent" and arming the first-deploy `services delete` branch below.
if ! existing="$(gcloud run services list \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --filter="metadata.name=${CLOUD_RUN_SERVICE}" \
  --format='value(metadata.name)' 2>&1)"; then
  echo "$existing" >&2
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
new_revision=""

rollback() {
  status=$?
  trap - ERR
  echo "Deployment failed; restoring previous Cloud Run traffic" >&2
  if [[ -n "$previous_revision" ]]; then
    gcloud run services update-traffic "$CLOUD_RUN_SERVICE" \
      --project="$GCP_PROJECT" --region="$GCP_REGION" \
      --to-revisions="${previous_revision}=100" --quiet >/dev/null || \
      echo "Cloud Run traffic rollback failed; operator action required" >&2
  elif [[ "$service_existed" == false && -n "$new_revision" ]]; then
    # A first Cloud Run deployment has no older revision that can receive
    # traffic. Delete only the service created by this failed first rollout so
    # an unhealthy revision is not left publicly reachable.
    gcloud run services delete "$CLOUD_RUN_SERVICE" \
      --project="$GCP_PROJECT" --region="$GCP_REGION" --quiet >/dev/null || \
      echo "Failed first deployment could not be removed; operator action required" >&2
  fi
  exit "$status"
}
trap rollback ERR

gcloud run deploy "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --image="$IMAGE" --platform=managed --no-traffic --tag="sha-${COMMIT_SHA}" \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" \
  --add-cloudsql-instances="$CLOUD_SQL_CONNECTION" \
  --set-env-vars="COMMIT_SHA=$COMMIT_SHA,ENVIRONMENT=staging,INTEGRATIONS_MODE=disabled" \
  --set-secrets="DATABASE_URL=${DATABASE_SECRET}:latest,GEMINI_API_KEY=${GEMINI_SECRET}:latest" \
  --command=/app/cloudrun-entrypoint.sh --port=8000 --min=1 --max=1 \
  --cpu=1 --memory=512Mi --no-cpu-throttling --allow-unauthenticated --quiet >/dev/null

new_revision="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --format='value(status.latestCreatedRevisionName)')"
[[ -n "$new_revision" ]]
revision_url="$(gcloud run services describe "$CLOUD_RUN_SERVICE" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" --format=json |
  jq -r --arg tag "sha-${COMMIT_SHA}" '.status.traffic[]? | select(.tag == $tag) | .url' | head -n 1)"
[[ "$revision_url" == https://* ]]

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
