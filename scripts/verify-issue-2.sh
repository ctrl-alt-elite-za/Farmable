#!/usr/bin/env bash
# Verifies issue #2's acceptance criteria end-to-end in a throwaway clone.
# Run from anywhere; it clones the current branch into a temp dir.
# Usage: scripts/verify-issue-2.sh [branch] [owner/repo]
set -euo pipefail

branch="${1:-$(git rev-parse --abbrev-ref HEAD)}"
repo_url="${2:-$(git config --get remote.origin.url)}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1" >&2; exit 1; }

echo "== cloning $repo_url @ $branch into $tmp =="
git clone --branch "$branch" --single-branch "$repo_url" "$tmp/repo"
cd "$tmp/repo"

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
mkdir -p backend/tmp_check
cat > backend/tmp_check/badly_formatted.py <<'PYEOF'
def f( x,y ):
    return x+y
PYEOF
git add backend/tmp_check/badly_formatted.py
if git commit -m "test: badly formatted python" >/tmp/commit.log 2>&1; then
  export PATH="$HOME/.local/bin:$PATH"
  uv run ruff format --check backend/tmp_check/badly_formatted.py \
    || fail "ruff format --check failed on the committed file"
  pass "badly formatted Python auto-fixed on commit"
else
  cat /tmp/commit.log
  fail "commit of badly formatted python did not succeed after autofix"
fi

echo "== gitleaks blocks a committed secret =="
echo "aws_key = \"AKIAIOSFODNN7EXAMPLE\"" > backend/tmp_check/leak.py # gitleaks:allow
git add backend/tmp_check/leak.py
if git commit -m "test: leaked secret" >/tmp/leak.log 2>&1; then
  fail "commit with a secret was NOT blocked"
else
  grep -qi "leak.py" /tmp/leak.log || fail "gitleaks output did not name the file"
  pass "gitleaks blocked the commit and named the file"
  git reset --hard HEAD >/dev/null
fi

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
if command -v gh >/dev/null 2>&1; then
  reviews=$(gh api repos/ctrl-alt-elite-za/Farmable/branches/main/protection \
    --jq '.required_pull_request_reviews.required_approving_review_count' 2>/dev/null || echo "0")
  force=$(gh api repos/ctrl-alt-elite-za/Farmable/branches/main/protection \
    --jq '.allow_force_pushes.enabled' 2>/dev/null || echo "true")
  [ "${reviews:-0}" -ge 1 ] || fail "required_approving_review_count < 1"
  [ "$force" = "false" ] || fail "force pushes are not blocked"
  pass "branch protection: reviews>=1, force pushes blocked"
else
  echo "SKIP: gh not available, skipping branch protection check"
fi

echo
echo "All checks passed."
