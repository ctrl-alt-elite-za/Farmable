#!/usr/bin/env bash
# Verifies issue #2's acceptance criteria end-to-end in a throwaway clone.
# Run from anywhere; it clones the current branch into a temp dir.
# Usage: scripts/verify-issue-2.sh [--allow-skips] [branch] [owner/repo]
#
# Exit codes: 0 = every check ran and passed
#             1 = a check failed
#             2 = all checks that ran passed, but some were skipped
#                 (partial verification; use --allow-skips to exit 0 instead)
set -euo pipefail

allow_skips=0
if [ "${1:-}" = "--allow-skips" ]; then
  allow_skips=1
  shift
fi

branch="${1:-$(git rev-parse --abbrev-ref HEAD)}"
repo_url="${2:-$(git config --get remote.origin.url)}"
repo_slug="$(echo "$repo_url" | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A plain counter and a newline-delimited list, not an array: referencing an
# empty array under `set -u` is an error in bash < 4.4, which macOS still ships.
skipped_count=0
skipped_list=""

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }
skip() {
  skipped_count=$((skipped_count + 1))
  skipped_list="${skipped_list}  - $1
"
  echo "SKIP: $1" >&2
}

echo "== cloning $repo_url @ $branch into $tmp =="
git clone --branch "$branch" --single-branch "$repo_url" "$tmp/repo"
cd "$tmp/repo"
[ "$branch" = "main" ] || git fetch origin main:refs/remotes/origin/main

echo "== make setup =="
make setup || fail "make setup did not exit 0"
pass "make setup"

echo "== make lint =="
make lint || fail "make lint did not exit 0"
pass "make lint"

echo "== make typecheck =="
make typecheck || fail "make typecheck did not exit 0"
pass "make typecheck"

echo "== badly formatted Python gets auto-fixed on commit =="
mkdir -p apps/backend/tmp_check
cat > apps/backend/tmp_check/badly_formatted.py <<'PYEOF'
def f( x,y ):
    return x+y
PYEOF
git add apps/backend/tmp_check/badly_formatted.py
if git commit -m "test: badly formatted python" >"$tmp/commit.log" 2>&1; then
  export PATH="$HOME/.local/bin:$PATH"
  uv run ruff format --check apps/backend/tmp_check/badly_formatted.py \
    || fail "ruff format --check failed on the committed file"
  pass "badly formatted Python auto-fixed on commit"
else
  cat "$tmp/commit.log"
  fail "commit of badly formatted python did not succeed after autofix"
fi

echo "== gitleaks blocks a committed secret =="
echo "aws_key = \"AKIAIOSFODNN7EXAMPLE\"" > apps/backend/tmp_check/leak.py # gitleaks:allow
git add apps/backend/tmp_check/leak.py
if git commit -m "test: leaked secret" >"$tmp/leak.log" 2>&1; then
  fail "commit with a secret was NOT blocked"
else
  grep -qi "leak.py" "$tmp/leak.log" || fail "gitleaks output did not name the file"
  pass "gitleaks blocked the commit and named the file"
  git reset --hard HEAD >/dev/null
fi

echo "== pre-push hook (scripts/changed-scopes.sh) catches raw SQL in apps/backend/ =="
mkdir -p apps/backend/tmp_check
cat > apps/backend/tmp_check/raw_sql.py <<'PYEOF'
def get_user(cursor, user_id):
    cursor.execute("select * from users where id = %s", (user_id,))
PYEOF
git add apps/backend/tmp_check/raw_sql.py
git commit -m "test: raw sql in backend" >"$tmp/rawsql-commit.log" 2>&1 \
  || { cat "$tmp/rawsql-commit.log"; fail "commit for the raw-SQL scope test did not succeed"; }
if scripts/changed-scopes.sh >"$tmp/changed-scopes.log" 2>&1; then
  cat "$tmp/changed-scopes.log"
  fail "changed-scopes.sh did not catch raw SQL added under apps/backend/"
else
  grep -qi "raw_sql.py" "$tmp/changed-scopes.log" || fail "changed-scopes.sh output did not name the file"
  pass "pre-push scope check (changed-scopes.sh) caught the raw SQL and named the file"
fi
git reset --hard HEAD~1 >/dev/null

echo "== dependabot.yml =="
for eco in pip npm github-actions; do
  grep -q "\"$eco\"\|'$eco'\|$eco" .github/dependabot.yml \
    || fail "dependabot.yml missing $eco"
done
pass "dependabot.yml lists pip, npm, github-actions"

echo "== AGENTS.md sections =="
for section in Setup Commands Conventions Secrets "Definition of Done"; do
  grep -q "$section" AGENTS.md || fail "AGENTS.md missing section: $section"
done
pass "AGENTS.md has all required sections"

echo "== branch protection on main (requires network + gh auth) =="
if ! command -v gh >/dev/null 2>&1; then
  skip "branch protection on main (gh CLI not available)"
elif ! protection="$(gh api "repos/$repo_slug/branches/main/protection" 2>/dev/null)"; then
  skip "branch protection on main (gh could not read the protection API: not authenticated, no network, or insufficient permissions)"
else
  reviews="$(echo "$protection" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(d.get("required_pull_request_reviews",{}).get("required_approving_review_count",0))')"
  force="$(echo "$protection" | python3 -c 'import json,sys; d=json.load(sys.stdin); print(str(d.get("allow_force_pushes",{}).get("enabled",True)).lower())')"
  [ "${reviews:-0}" -ge 1 ] || fail "required_approving_review_count < 1"
  [ "$force" = "false" ] || fail "force pushes are not blocked"
  pass "branch protection: reviews>=1, force pushes blocked"
fi

echo
if [ "$skipped_count" -eq 0 ]; then
  echo "All checks passed."
  exit 0
fi

echo "PARTIAL VERIFICATION: $skipped_count check(s) could not be run:" >&2
printf '%s' "$skipped_list" >&2
echo "Every check that ran passed, but this is NOT a full verification." >&2
[ "$allow_skips" -eq 1 ] && exit 0
exit 2
