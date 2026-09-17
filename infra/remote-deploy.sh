#!/usr/bin/env bash
set -euo pipefail

# Executed by SSM on the staging instance. Secrets are retrieved locally from
# SSM; no secret is sent in the SSM command, written to the image, or logged.
: "${IMAGE_TAG:?IMAGE_TAG is required}"
: "${ECR_REGISTRY:?ECR_REGISTRY is required}"
: "${COMMIT_SHA:?COMMIT_SHA is required}"

cd /opt/farmable
DATABASE_URL="$(aws ssm get-parameter --name /farmable/staging/database-url --with-decryption --query Parameter.Value --output text)"
POSTGRES_PASSWORD="$(aws ssm get-parameter --name /farmable/staging/postgres-password --with-decryption --query Parameter.Value --output text)"
CADDY_DOMAIN="$(aws ssm get-parameter --name /farmable/staging/caddy-domain --query Parameter.Value --output text)"
CURRENT_TAG="$(aws ssm get-parameter --name /farmable/staging/current-image-tag --query Parameter.Value --output text 2>/dev/null || true)"
ECR_PASSWORD="$(aws ecr get-login-password --region af-south-1)"
curl -fsSL "https://raw.githubusercontent.com/ctrl-alt-elite-za/Farmable/${COMMIT_SHA}/compose.yaml" -o compose.yaml
curl -fsSL "https://raw.githubusercontent.com/ctrl-alt-elite-za/Farmable/${COMMIT_SHA}/infra/compose.staging.yaml" -o compose.staging.yaml
mkdir -p infra
curl -fsSL "https://raw.githubusercontent.com/ctrl-alt-elite-za/Farmable/${COMMIT_SHA}/infra/Caddyfile" -o infra/Caddyfile
cat > .env <<EOF
DATABASE_URL=$DATABASE_URL
POSTGRES_USER=farmable
POSTGRES_PASSWORD=$POSTGRES_PASSWORD
POSTGRES_DB=farmable
COMMIT_SHA=$COMMIT_SHA
LOG_LEVEL=info
CADDY_DOMAIN=$CADDY_DOMAIN
EOF
chmod 0600 .env

docker login --username AWS --password-stdin "$ECR_REGISTRY" <<< "$ECR_PASSWORD" >/dev/null
docker pull "$ECR_REGISTRY/farmable-backend:$IMAGE_TAG"
export FARMABLE_BACKEND_IMAGE="$ECR_REGISTRY/farmable-backend:$IMAGE_TAG"

docker compose --env-file .env -f compose.yaml -f compose.staging.yaml run --rm migrate
docker compose --env-file .env -f compose.yaml -f compose.staging.yaml run --rm queue-schema
docker compose --env-file .env -f compose.yaml -f compose.staging.yaml up -d --no-build api worker
aws ssm put-parameter --name /farmable/staging/previous-image-tag --type String --value "${CURRENT_TAG:-unknown}" --overwrite >/dev/null
aws ssm put-parameter --name /farmable/staging/current-image-tag --type String --value "$IMAGE_TAG" --overwrite >/dev/null
docker image prune -af --filter 'until=168h'
rm -f .env
