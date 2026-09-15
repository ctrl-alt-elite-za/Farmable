#!/usr/bin/env bash
# Fails if backend/ or migrations/ contain hand-written SQL. Per #3/#2:
# every database access must go through the SQLAlchemy ORM / GeoAlchemy2 —
# no text(), no SQL strings passed to execute(), no op.execute() in Alembic,
# no raw cursors. This is a defense against SQL injection, not a style rule.
set -euo pipefail

dirs=()
[ -d backend ] && dirs+=(backend)
[ -d migrations ] && dirs+=(migrations)

if [ ${#dirs[@]} -eq 0 ]; then
  echo "no backend/ or migrations/ yet, skipping"
  exit 0
fi

# Avoid \b and \s: GNU grep -E supports them as extensions but BSD/macOS
# grep -E does not, and this now runs on every contributor's push (via
# scripts/changed-scopes.sh), not just Linux CI.
pattern="([^A-Za-z0-9_]|^)text\(|\.execute\([[:space:]]*[\"']|op\.execute\(|([^A-Za-z0-9_]|^)cursor\(\)"
if hits=$(grep -RInE --include='*.py' "$pattern" "${dirs[@]}"); then
  echo "Hand-written SQL found (forbidden — use the ORM instead):" >&2
  echo "$hits" >&2
  exit 1
fi

echo "no raw SQL found"
