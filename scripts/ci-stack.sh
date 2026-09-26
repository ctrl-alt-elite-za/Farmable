#!/usr/bin/env bash
# Fresh production deploy/smoke/E2E proof. Every invocation owns its entire stack.
set -euo pipefail
cd "$(dirname "$0")/.."
mode="${1:?Choose deployability, e2e-api, e2e-degradation or mobile}"
case "$mode" in deployability|e2e-api|e2e-degradation|mobile) ;; *) exit 2 ;; esac
docker info >/dev/null
export POSTGRES_USER=farmable_ci POSTGRES_DB=farmable_ci
export ENVIRONMENT=ci INTEGRATIONS_MODE=fake
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
    adb logcat -d -s AndroidRuntime:E flutter:E > .ci-mobile-debug/android-errors.log 2>&1 || true
    adb exec-out screencap -p > .ci-mobile-debug/screen.png 2>/dev/null || true
    adb shell uiautomator dump /sdcard/farmable-ci-ui.xml >/dev/null 2>&1 || true
    adb pull /sdcard/farmable-ci-ui.xml .ci-mobile-debug/ui.xml >/dev/null 2>&1 || true
  fi
  "${compose[@]}" down --volumes --remove-orphans
  return "$status"
}
trap cleanup EXIT
"${compose[@]}" build api worker
if [ "$mode" = deployability ]; then
  # Build the post-migration importer too; no live DB or notifier credential in CI.
  docker build --file apps/backend/Dockerfile --target forecast-import .
fi
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
  # Every wait is bounded inside the helper — see scripts/await-device.sh
  # for why adb wait-for-device and each probe each need their own limit.
  bash scripts/await-device.sh
  adb install -r "${APK:?Set APK to the test-mode Android build}"
  # And again after the install, because the gate above proves nothing about
  # the moment after a slow step. Streaming a release APK takes seconds, and
  # PR #53's run passed the first check, installed successfully, then failed
  # Maestro's very first command with "device offline" — the transport went
  # away inside that window.
  bash scripts/await-device.sh
  # Prove connectivity, then stop ONLY this invocation's API for offline proof.
  maestro test e2e/mobile/online_launch.yaml
  # Real sign-up and login against this stack's API. INTEGRATIONS_MODE=fake
  # gives a deterministic OTP provider (111111 phone, 222222 email), so the
  # flows prove the client end to end without any SMS or mail leaving CI.
  bash scripts/await-device.sh
  maestro test e2e/mobile/signup.yaml
  bash scripts/await-device.sh
  maestro test e2e/mobile/login.yaml
  bash scripts/await-device.sh
  maestro test e2e/mobile/scan_pan.yaml
  # A fresh install's whole first launch (#89): intro, onboarding, sign-up,
  # first farm and first section, Home, and a second launch that skips it all.
  # Last before the API stops, because it leaves an account signed in for the
  # two dashboard flows below.
  bash scripts/await-device.sh
  maestro test e2e/mobile/first_launch_setup.yaml
  "${compose[@]}" stop api
  # Home with the API down, then a cold start in airplane mode (#12).
  bash scripts/await-device.sh
  maestro test e2e/mobile/dashboard_degraded.yaml
  bash scripts/await-device.sh
  maestro test e2e/mobile/dashboard_offline.yaml
  bash scripts/await-device.sh
  maestro test e2e/mobile/offline_launch.yaml
fi
