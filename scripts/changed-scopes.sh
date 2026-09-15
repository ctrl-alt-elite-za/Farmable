#!/usr/bin/env bash
# Pre-push hook: for each top-level folder touched since the remote's version
# of this branch, run lint (with autofix), typecheck and fast unit tests for
# just that folder. Keeps pre-push fast by never touching untouched folders.
# See #2's "problems caught in seconds on the laptop" pre-push requirement.
set -euo pipefail

export PATH="$HOME/.local/bin:$PATH"

remote="${1:-@{push}}"
base="$(git merge-base HEAD "$remote" 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || echo "")"

if [ -z "$base" ]; then
  echo "no merge base found, running full lint/typecheck/test instead"
  make lint typecheck test
  exit $?
fi

changed_dirs="$(git diff --name-only "$base"...HEAD | cut -d/ -f1 | sort -u)"

if [ -z "$changed_dirs" ]; then
  echo "no changes since $base, skipping"
  exit 0
fi

status=0
for dir in $changed_dirs; do
  case "$dir" in
    backend)
      if [ -n "$(find backend -name '*.py' 2>/dev/null)" ]; then
        uv run ruff check --fix backend || status=1
        uv run mypy backend || status=1
        [ -n "$(find backend -name 'test_*.py' -o -name '*_test.py' 2>/dev/null)" ] && { uv run pytest backend -q || status=1; }
      fi
      ;;
    ml)
      if [ -n "$(find ml -name '*.py' 2>/dev/null)" ]; then
        uv run ruff check --fix ml || status=1
        uv run mypy ml || status=1
      fi
      ;;
    apps|packages)
      pnpm --filter "./$dir/**" --if-present run lint -- --fix || status=1
      pnpm --filter "./$dir/**" --if-present run typecheck || status=1
      pnpm --filter "./$dir/**" --if-present run test || status=1
      ;;
    *)
      : # not a code scope (docs, infra config, etc.) — nothing to run
      ;;
  esac
done

exit $status
