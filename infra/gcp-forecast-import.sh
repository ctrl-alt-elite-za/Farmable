#!/usr/bin/env bash
# Trusted post-migration operation. Never turn a forecast failure into a failed
# application deployment; the transactional importer retains the active run.
set -Eeuo pipefail

warn() { echo '::warning::Forecast import incomplete; inspect the import job. Existing active data is retained unless a validated run committed.'; }
trap 'warn; exit 0' ERR

mode="${FORECAST_DATA_MODE:-disabled}"
case "$mode" in
  disabled) echo 'Forecast import disabled; no job executed'; exit 0 ;;
  sample|historical) ;;
  *) warn; exit 0 ;;
esac

# Validate before building. Values become gcloud list entries, never shell code.
for name in GCP_PROJECT GCP_REGION FORECAST_IMPORT_ACCOUNT DATABASE_SECRET \
  CLOUD_SQL_CONNECTION FORECAST_GITHUB_TOKEN_SECRET; do
  value="${!name:-}"
  if [[ -z "$value" || ! "$value" =~ ^[a-zA-Z0-9_@./:-]+$ ]]; then
    warn
    exit 0
  fi
done
[[ "${COMMIT_SHA:-}" =~ ^[0-9a-f]{40}$ ]]
[[ "${ARTIFACT_REPOSITORY:-}" =~ ^[a-z0-9.-]+-docker\.pkg\.dev/[a-z0-9-]+/[a-z0-9_-]+$ ]]
job="${FORECAST_IMPORT_JOB:-farmable-forecast-import}"
[[ "$job" =~ ^[a-z][a-z0-9-]{0,62}$ ]]
image="${ARTIFACT_REPOSITORY}/forecast-import:${COMMIT_SHA}"

timeout 300s docker build --file apps/backend/Dockerfile --target forecast-import --tag "$image" .
timeout 120s docker push "$image"
timeout 60s gcloud run jobs deploy "$job" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" \
  --image="$image" --service-account="$FORECAST_IMPORT_ACCOUNT" \
  --set-cloudsql-instances="$CLOUD_SQL_CONNECTION" \
  --set-secrets="DATABASE_URL=${DATABASE_SECRET}:latest,FORECAST_GITHUB_TOKEN=${FORECAST_GITHUB_TOKEN_SECRET}:latest" \
  --set-env-vars="ENVIRONMENT=staging,FORECAST_DATA_MODE=${mode},FORECAST_GITHUB_ENABLED=true,FORECAST_GITHUB_REPOSITORY=ctrl-alt-elite-za/Farmable" \
  --command=python --args=-m,farmable_backend.forecast_cli,import-latest,--root,/app/ml/forecast/results \
  --tasks=1 --parallelism=1 --max-retries=0 --task-timeout=300s --quiet
timeout 330s gcloud run jobs execute "$job" \
  --project="$GCP_PROJECT" --region="$GCP_REGION" --wait --quiet
echo 'Forecast import job completed; inspect its validation/notification warnings'
