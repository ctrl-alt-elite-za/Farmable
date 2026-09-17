#!/usr/bin/env bash
# Own only this random project's containers. No host ports or persistent volumes.
set -euo pipefail
cd "$(dirname "$0")/.."
command -v docker >/dev/null || { echo "Docker is required" >&2; exit 1; }
docker info >/dev/null || { echo "Start Docker first" >&2; exit 1; }
UPLOAD_TEST_USER="$(uv run python -c 'import secrets; print(secrets.token_hex(12))')"
UPLOAD_TEST_PASSWORD="$(uv run python -c 'import secrets; print(secrets.token_hex(24))')"
export UPLOAD_TEST_USER UPLOAD_TEST_PASSWORD
project="farmable-uploads-$(uv run python -c 'import uuid; print(uuid.uuid4().hex)')"
compose=(docker compose -p "$project" -f compose.uploads.yaml)
cleanup() { "${compose[@]}" down --remove-orphans; }
trap cleanup EXIT
"${compose[@]}" build
"${compose[@]}" up -d --wait minio
"${compose[@]}" run --rm --no-deps upload-tests
