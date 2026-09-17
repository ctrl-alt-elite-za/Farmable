#!/usr/bin/env bash
# Fresh production deploy/smoke/E2E proof. Every invocation owns its entire stack.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:?Choose deployability, e2e-api, e2e-degradation or mobile}"
case "$mode" in deployability|e2e-api|e2e-degradation|mobile) ;; *) exit 2 ;; esac
docker info >/dev/null
export POSTGRES_USER=farmable_ci POSTGRES_DB=farmable_ci
POSTGRES_PASSWORD="$(uv run python -c 'import secrets; print(secrets.token_hex(24))')"
export POSTGRES_PASSWORD
DATABASE_URL="$(uv run python -c 'import os; from sqlalchemy import URL; print(URL.create("postgresql+psycopg", username=os.environ["POSTGRES_USER"], password=os.environ["POSTGRES_PASSWORD"], host="database", database=os.environ["POSTGRES_DB"]).render_as_string(hide_password=False))')"
export DATABASE_URL
if [ "${GITHUB_ACTIONS:-}" = true ]; then
  printf '::add-mask::%s\n' "$POSTGRES_PASSWORD" "$DATABASE_URL"
fi
COMMIT_SHA="$(git rev-parse HEAD)"
export COMMIT_SHA API_PORT=0
if [ "$mode" = mobile ]; then export API_PORT=8000; fi
project="farmable-ci-$(uv run python -c 'import uuid; print(uuid.uuid4().hex)')"
compose=(docker compose -p "$project" -f compose.yaml)
cleanup() {
  local status=$?
  if [ "$mode" = mobile ] && [ "$status" -ne 0 ]; then
    # Capture while the owned emulator is still running; the runner stops it next.
    # Only app/platform error tags, never environment or backend/provider logs.
    mkdir -p .ci-mobile-debug
    adb logcat -d -s AndroidRuntime:E ReactNativeJS:E > .ci-mobile-debug/android-errors.log 2>&1 || true
    adb exec-out screencap -p > .ci-mobile-debug/screen.png 2>/dev/null || true
    adb shell uiautomator dump /sdcard/farmable-ci-ui.xml >/dev/null 2>&1 || true
    adb pull /sdcard/farmable-ci-ui.xml .ci-mobile-debug/ui.xml >/dev/null 2>&1 || true
  fi
  "${compose[@]}" down --volumes --remove-orphans
  return "$status"
}
trap cleanup EXIT
"${compose[@]}" build api worker
"${compose[@]}" up -d --wait database
"${compose[@]}" run --rm migrate
"${compose[@]}" run --rm queue-schema
"${compose[@]}" up -d api worker
"${compose[@]}" run --rm tests pytest e2e/api -m integration -q -p no:cacheprovider
if [ "$mode" = e2e-degradation ]; then
  "${compose[@]}" stop worker
  "${compose[@]}" run --rm tests pytest e2e/degradation -m integration -q -k worker_down -p no:cacheprovider
  "${compose[@]}" start worker
  "${compose[@]}" run --rm tests pytest e2e/degradation -m integration -q -k recovered -p no:cacheprovider
  "${compose[@]}" stop database
  "${compose[@]}" run --rm --no-deps tests pytest e2e/degradation -m integration -q -k database_down -p no:cacheprovider
elif [ "$mode" = mobile ]; then
  adb install -r "${APK:?Set APK to the test-mode Android build}"
  # Prove connectivity, then stop ONLY this invocation's API for offline proof.
  maestro test e2e/mobile/online_launch.yaml
  if [ -f e2e/mobile/scan_pan_test_mode.yaml ]; then
    maestro test e2e/mobile/scan_pan_test_mode.yaml
  fi
  "${compose[@]}" stop api
  maestro test e2e/mobile/offline_launch.yaml
fi
