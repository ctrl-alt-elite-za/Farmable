#!/usr/bin/env bash
# Fails if apps/backend/ or migrations/ contain hand-written SQL.
# Database access must go through the ORM only.
set -euo pipefail

dirs=()
[ -d apps/backend ] && dirs+=(apps/backend)
[ -d migrations ] && dirs+=(migrations)

if [ ${#dirs[@]} -eq 0 ]; then
  echo "no apps/backend/ or migrations/ yet, skipping"
  exit 0
fi

# No \b/\s: those are GNU-only grep -E extensions, not portable to BSD/macOS.
pattern="([^A-Za-z0-9_]|^)text\(|\.execute\([[:space:]]*[\"']|op\.execute\(|([^A-Za-z0-9_]|^)cursor\(\)"
if hits=$(grep -RInE --include='*.py' "$pattern" "${dirs[@]}"); then
  echo "Hand-written SQL found (forbidden — use the ORM instead):" >&2
  echo "$hits" >&2
  exit 1
fi

echo "no raw SQL found"
