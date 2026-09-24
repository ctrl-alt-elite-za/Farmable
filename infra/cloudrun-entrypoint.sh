#!/usr/bin/env bash
set -Eeuo pipefail

# Cloud Run supplies one HTTP container, while the API readiness contract also
# requires the Procrastinate heartbeat. Keep one bounded demo instance for both
# processes; the local Compose topology remains API + worker as before.

start_worker() {
  python -m farmable_backend.worker &
  worker_pid=$!
}

start_worker
uvicorn farmable_backend.main:app \
  --host 0.0.0.0 --port "${PORT:-8000}" --no-proxy-headers \
  --no-access-log --log-config apps/backend/logging.json &
api_pid=$!

cleanup() {
  trap - EXIT INT TERM
  kill "$worker_pid" "$api_pid" 2>/dev/null || true
  wait "$worker_pid" "$api_pid" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

# The API is the process Cloud Run routes traffic to, so only its exit ends the
# container. A worker exit used to end it too: `wait -n` returns on whichever child
# finishes first and the EXIT trap then killed the other, so a fault in the background
# queue took the HTTP service down with it -- and at --max=1 that is total downtime for
# a service whose queue currently carries no demo-critical work.
#
# Restarting the worker does not weaken the deploy gate. /health/ready reads the
# heartbeat from procrastinate_workers in Postgres rather than from this process table,
# so a worker that cannot stay alive still leaves the heartbeat stale, still fails
# readiness, and still triggers the fail-closed rollback in gcp-rollout.sh.
while kill -0 "$api_pid" 2>/dev/null; do
  if ! kill -0 "$worker_pid" 2>/dev/null; then
    # Reap it so the restarted worker does not accumulate zombies beside it.
    wait "$worker_pid" 2>/dev/null || true
    echo "Procrastinate worker exited; restarting it and leaving the API serving" >&2
    sleep 1
    start_worker
  fi
  sleep 1
done

# Surface the API's own exit status as the container's.
wait "$api_pid"
