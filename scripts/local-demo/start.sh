#!/usr/bin/env bash
# Starts the local fallback demo backend: PostgreSQL on 5433, the API on
# 127.0.0.1:8000 and the worker. Logs and state live in ~/.farmable-local.
set -euo pipefail
cd "$(dirname "$0")/../.."
state="$HOME/.farmable-local"
pgbin=/usr/lib/postgresql/14/bin
# shellcheck source=/dev/null
source scripts/local-demo/env.sh
if ! "$pgbin/pg_isready" -q -h 127.0.0.1 -p 5433; then
  "$pgbin/pg_ctl" -D "$state/pg" -o "-p 5433 -k $state -c listen_addresses=127.0.0.1" \
    -l "$state/pg.log" start >/dev/null
  sleep 2
fi
uv run alembic upgrade head >/dev/null
if [ -f "$state/api.pid" ] && kill -0 "$(cat "$state/api.pid")" 2>/dev/null; then
  echo "API already running (pid $(cat "$state/api.pid"))"
else
  nohup uv run uvicorn farmable_backend.main:app --host 127.0.0.1 --port 8000 \
    >"$state/api.log" 2>&1 & echo $! >"$state/api.pid"
fi
if [ -f "$state/worker.pid" ] && kill -0 "$(cat "$state/worker.pid")" 2>/dev/null; then
  echo "Worker already running (pid $(cat "$state/worker.pid"))"
else
  nohup uv run python -m farmable_backend.worker >"$state/worker.log" 2>&1 &
  echo $! >"$state/worker.pid"
fi
for _ in $(seq 1 60); do
  if curl -fsS http://127.0.0.1:8000/health/ready >/dev/null 2>&1; then
    echo "Local demo backend ready: http://127.0.0.1:8000"
    exit 0
  fi
  sleep 1
done
echo "Backend did not become ready; see $state/api.log and $state/worker.log" >&2
exit 1
