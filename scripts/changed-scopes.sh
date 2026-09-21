#!/usr/bin/env bash
# Pre-push hook: for each app/folder touched since origin/main, run lint
# (with autofix), typecheck and fast unit tests for just that scope.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

base="$(git merge-base HEAD origin/main 2>/dev/null || echo "")"

if [ -z "$base" ]; then
  echo "no merge base found, running full lint/typecheck/test instead"
  make lint typecheck test
  exit $?
fi

# Two path segments under apps/ (apps/backend, not just apps), one otherwise.
changed_dirs="$(git diff --name-only "$base"...HEAD \
  | awk -F/ '{ if ($1 == "apps" && NF >= 2) print $1"/"$2; else print $1 }' \
  | sort -u)"

if [ -z "$changed_dirs" ]; then
  echo "no changes since $base, skipping"
  exit 0
fi

status=0
sql_check_needed=0
for dir in $changed_dirs; do
  case "$dir" in
    apps/backend)
      sql_check_needed=1
      if [ -n "$(scripts/has-py-files.sh apps/backend)" ]; then
        uv run ruff check --fix apps/backend || status=1
        uv run mypy apps/backend || status=1
        [ -n "$(find apps/backend -name 'test_*.py' -o -name '*_test.py' 2>/dev/null)" ] && { uv run pytest apps/backend -q || status=1; }
      fi
      ;;
    apps/ml-service)
      if [ -n "$(scripts/has-py-files.sh apps/ml-service)" ]; then
        uv run ruff check --fix apps/ml-service || status=1
        uv run mypy apps/ml-service || status=1
      fi
      ;;
    migrations)
      sql_check_needed=1
      ;;
    scripts)
      if [ -n "$(scripts/has-py-files.sh scripts)" ]; then
        uv run ruff check --fix scripts || status=1
        uv run mypy scripts || status=1
        [ -d scripts/tests ] && { uv run pytest scripts/tests -q || status=1; }
      fi
      ;;
  esac
done

# The wrapper scans both SQL scopes, so run it only once even if both changed.
if [ "$sql_check_needed" -eq 1 ]; then
  scripts/check-no-raw-sql.sh || status=1
fi

# JS/TS packages: pnpm's git-diff-aware filter resolves which changed.
pnpm --filter "...[$base]" --if-present run lint -- --fix || status=1
pnpm --filter "...[$base]" --if-present run typecheck || status=1
pnpm --filter "...[$base]" --if-present run test || status=1

exit $status
