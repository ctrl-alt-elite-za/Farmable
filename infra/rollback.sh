#!/usr/bin/env bash
set -euo pipefail
: "${ECR_REGISTRY:?ECR_REGISTRY is required}"
: "${BACKUP_KEY:?BACKUP_KEY is required}"

cd /opt/farmable
POSTGRES_PASSWORD="$(aws ssm get-parameter --name /farmable/staging/postgres-password --with-decryption --query Parameter.Value --output text)"
DATABASE_URL="$(aws ssm get-parameter --name /farmable/staging/database-url --with-decryption --query Parameter.Value --output text)"
CADDY_DOMAIN="$(aws ssm get-parameter --name /farmable/staging/caddy-domain --query Parameter.Value --output text)"
printf 'DATABASE_URL=%s\nPOSTGRES_USER=farmable\nPOSTGRES_PASSWORD=%s\nPOSTGRES_DB=farmable\nCADDY_DOMAIN=%s\n' "$DATABASE_URL" "$POSTGRES_PASSWORD" "$CADDY_DOMAIN" > .env
PREVIOUS_TAG="$(aws ssm get-parameter --name /farmable/staging/previous-image-tag --query Parameter.Value --output text)"
BACKUP_BUCKET="$(aws ssm get-parameter --name /farmable/staging/backup-bucket --query Parameter.Value --output text)"
test "$PREVIOUS_TAG" != unknown
aws ecr get-login-password --region af-south-1 | docker login --username AWS --password-stdin "$ECR_REGISTRY" >/dev/null
docker pull "$ECR_REGISTRY/farmable-backend:$PREVIOUS_TAG"
export FARMABLE_BACKEND_IMAGE="$ECR_REGISTRY/farmable-backend:$PREVIOUS_TAG"
aws s3 cp "s3://$BACKUP_BUCKET/$BACKUP_KEY" /tmp/farmable-backup.dump --sse AES256
docker compose --env-file .env -f compose.yaml -f compose.staging.yaml exec -T database \
  pg_restore --clean --if-exists --no-owner --no-privileges -U farmable -d farmable < /tmp/farmable-backup.dump
docker compose --env-file .env -f compose.yaml -f compose.staging.yaml up -d --no-build api worker
rm -f /tmp/farmable-backup.dump .env
