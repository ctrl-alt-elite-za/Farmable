#!/usr/bin/env bash
# Use the code version serving live traffic, not whatever main contains tonight.
set -Eeuo pipefail

for name in GCP_PROJECT GCP_REGION RUNTIME_SERVICE_ACCOUNT DATABASE_SECRET CLOUD_SQL_CONNECTION; do
  value="${!name:-}"
  if [[ -z "$value" || ! "$value" =~ ^[a-zA-Z0-9_@./:-]+$ ]]; then
    echo 'Outlook smoke configuration invalid' >&2
    exit 1
  fi
done
[[ "${COMMIT_SHA:-}" =~ ^[0-9a-f]{40}$ ]]
[[ "${ARTIFACT_REPOSITORY:-}" =~ ^[a-z0-9.-]+-docker\.pkg\.dev/[a-z0-9-]+/[a-z0-9_-]+$ ]]
[[ "${API_URL:-}" =~ ^https://[a-z0-9-]+(\.[a-z0-9-]+)*\.run\.app$ ]]
case "${FORECAST_DATA_MODE:-disabled}" in sample|historical) ;; *)
  echo 'Outlook smoke requires an explicitly enabled forecast data mode' >&2; exit 1 ;;
esac
job=farmable-outlook-smoke
timeout 60s gcloud run jobs deploy "$job" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --image="${ARTIFACT_REPOSITORY}/backend:${COMMIT_SHA}" \
  --service-account="$RUNTIME_SERVICE_ACCOUNT" \
  --set-cloudsql-instances="$CLOUD_SQL_CONNECTION" \
  --set-secrets="DATABASE_URL=${DATABASE_SECRET}:latest" \
  --set-env-vars="ENVIRONMENT=staging,OUTLOOK_SMOKE_API_URL=${API_URL},FORECAST_DATA_MODE=${FORECAST_DATA_MODE},COMMIT_SHA=${COMMIT_SHA}" \
  --command=python --args=-m,farmable_backend.outlook_smoke \
  --tasks=1 --parallelism=1 --max-retries=0 --task-timeout=180s --quiet
timeout 210s gcloud run jobs execute "$job" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" --wait --quiet
