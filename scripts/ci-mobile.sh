#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "${1:-}" = build ]; then
  export EXPO_PUBLIC_TEST_MODE=1 EXPO_PUBLIC_API_URL=http://10.0.2.2:8000
  pnpm -C apps/mobile exec expo prebuild --platform android --no-install
  # A standalone JS bundle is required: debug/dev-client builds need Metro.
  # The CI emulator is x86_64; compiling the other three ABIs wastes its budget.
  (cd apps/mobile/android && ./gradlew assembleRelease --no-daemon --build-cache -PreactNativeArchitectures=x86_64)
else
  [ -d e2e/mobile ] || { echo 'prerequisite: Maestro flows wait for #4'; exit 1; }
  command -v maestro >/dev/null || { echo 'prerequisite: install Maestro cli-2.10.0'; exit 1; }
  command -v adb >/dev/null || { echo 'prerequisite: start an Android emulator'; exit 1; }
  bash scripts/ci-stack.sh mobile
fi
