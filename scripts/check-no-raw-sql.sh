#!/usr/bin/env bash
# Fails if apps/backend/ or migrations/ contain hand-written SQL.
# Database access must go through the ORM only.
# The actual check is AST-based (scripts/check_no_raw_sql.py) so that calls
# spanning multiple lines are detected too.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

dirs=()
[ -d apps/backend ] && dirs+=(apps/backend)
[ -d migrations ] && dirs+=(migrations)

if [ ${#dirs[@]} -eq 0 ]; then
  echo "no apps/backend/ or migrations/ yet, skipping"
  exit 0
fi

if command -v uv >/dev/null 2>&1; then
  exec uv run --no-project python scripts/check_no_raw_sql.py "${dirs[@]}"
fi
exec python3 scripts/check_no_raw_sql.py "${dirs[@]}"
