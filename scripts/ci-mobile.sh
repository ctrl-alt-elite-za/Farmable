#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = build ]; then
  (cd apps/mobile && flutter pub get && flutter build apk --release --dart-define=API_BASE_URL=http://10.0.2.2:8000)
else
  [ -d e2e/mobile ] || { echo 'prerequisite: Maestro flows wait for #4'; exit 1; }
  command -v maestro >/dev/null || { echo 'prerequisite: install Maestro cli-2.10.0'; exit 1; }
  command -v adb >/dev/null || { echo 'prerequisite: start an Android emulator'; exit 1; }
  bash scripts/ci-stack.sh mobile
fi
