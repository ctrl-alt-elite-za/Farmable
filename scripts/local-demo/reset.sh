#!/usr/bin/env bash
# Wipes the LOCAL fallback database and rebuilds it empty (migrations, queue
# schema, forecasts). Stops the API and worker first. Local only.
set -euo pipefail
cd "$(dirname "$0")/../.."
state="$HOME/.farmable-local"
bash scripts/local-demo/stop.sh >/dev/null
/usr/lib/postgresql/14/bin/pg_ctl -D "$state/pg" -o "-p 5433 -k $state -c listen_addresses=127.0.0.1" \
  -l "$state/pg.log" start >/dev/null
sleep 2
psql -q -h 127.0.0.1 -p 5433 -U farmable -d postgres -c "drop database if exists farmable" \
  -c "create database farmable"
# shellcheck source=/dev/null
source scripts/local-demo/env.sh
uv run alembic upgrade head >/dev/null
uv run python -m farmable_backend.manage queue-schema >/dev/null 2>&1
uv run python -m farmable_backend.forecast_cli import-latest --root ml/forecast/results
bash scripts/local-demo/start.sh
