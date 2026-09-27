#!/usr/bin/env bash
# Stops the local fallback demo backend. The database keeps its data.
set -uo pipefail
state="$HOME/.farmable-local"
for name in api worker; do
  if [ -f "$state/$name.pid" ]; then
    pkill -TERM -P "$(cat "$state/$name.pid")" 2>/dev/null
    kill "$(cat "$state/$name.pid")" 2>/dev/null
    rm -f "$state/$name.pid"
  fi
done
/usr/lib/postgresql/14/bin/pg_ctl -D "$state/pg" stop -m fast >/dev/null 2>&1
echo "Local demo backend stopped (data kept in $state/pg)"
