#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = build ]; then
  # 10.0.2.2 is the emulator's route to the host. This is an emulator-only
  # build: mobile-api.mjs rejects this address for anything shipped to a phone.
  # Test mode replays recorded frames so camera screens run without a camera.
  #
  # x86_64 only — the CI emulator is x86_64 and compiling the other ABIs wastes
  # its budget. A release build is required because a debug build needs a
  # running Dart VM service the E2E harness does not provide.
  (cd apps/mobile && flutter build apk --release \
    --target-platform android-x64 \
    --dart-define=TEST_MODE=true \
    --dart-define=API_URL=http://10.0.2.2:8000)
else
  [ -d e2e/mobile ] || { echo 'prerequisite: Maestro flows wait for #4'; exit 1; }
  command -v maestro >/dev/null || { echo 'prerequisite: install Maestro cli-2.10.0'; exit 1; }
  command -v adb >/dev/null || { echo 'prerequisite: start an Android emulator'; exit 1; }
  bash scripts/ci-stack.sh mobile
fi
