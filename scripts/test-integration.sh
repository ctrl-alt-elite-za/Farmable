#!/usr/bin/env bash
# Every run owns a unique Compose project and disposable volume; never touches the dev DB.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo "Docker is required" >&2; exit 1; }
docker info >/dev/null || { echo "Start Docker Desktop/the Docker engine first" >&2; exit 1; }
export POSTGRES_USER=farmable_test POSTGRES_DB=farmable_test
POSTGRES_PASSWORD="$(uv run python -c 'import secrets; print(secrets.token_hex(24))')"
export POSTGRES_PASSWORD
DATABASE_URL="$(uv run python -c 'import os; from sqlalchemy import URL; print(URL.create("postgresql+psycopg", username=os.environ["POSTGRES_USER"], password=os.environ["POSTGRES_PASSWORD"], host="database", port=5432, database=os.environ["POSTGRES_DB"]).render_as_string(hide_password=False))')"
export DATABASE_URL
COMMIT_SHA="$(git rev-parse HEAD)"
export COMMIT_SHA
export API_PORT=0 # Docker chooses a free localhost port; cannot collide with the dev API.
project="farmable-test-$(uv run python -c 'import uuid; print(uuid.uuid4().hex)')"
compose=(docker compose -p "$project" -f compose.yaml)
cleanup() { "${compose[@]}" down --volumes --remove-orphans; }
trap cleanup EXIT
"${compose[@]}" build
"${compose[@]}" up -d --wait database
"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm queue-schema
"${compose[@]}" up -d api worker
"${compose[@]}" run --rm tests pytest apps/backend/tests/integration -m integration -q -k 'healthy or models_match_migrations or vision_registry'
"${compose[@]}" stop worker
# Readiness must reject stale heartbeats, not just the absence of job failures.
"${compose[@]}" run --rm tests pytest apps/backend/tests/integration -m integration -q -k worker_down
"${compose[@]}" start worker
"${compose[@]}" run --rm tests pytest apps/backend/tests/integration -m integration -q -k recovered
"${compose[@]}" stop database
"${compose[@]}" run --rm --no-deps tests pytest apps/backend/tests/integration -m integration -q -k database_down
