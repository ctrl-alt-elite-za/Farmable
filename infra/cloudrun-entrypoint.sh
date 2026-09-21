#!/usr/bin/env bash
set -Eeuo pipefail

# Cloud Run supplies one HTTP container, while the API readiness contract also
# requires the Procrastinate heartbeat. Keep one bounded demo instance for both
# processes; the local Compose topology remains API + worker as before.
python -m farmable_backend.worker &
worker_pid=$!
uvicorn farmable_backend.main:app \
  --host 0.0.0.0 --port "${PORT:-8000}" --no-proxy-headers \
  --no-access-log --log-config apps/backend/logging.json &
api_pid=$!

cleanup() {
  kill "$worker_pid" "$api_pid" 2>/dev/null || true
  wait "$worker_pid" "$api_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM
wait -n "$worker_pid" "$api_pid"
