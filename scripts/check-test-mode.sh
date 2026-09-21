#!/usr/bin/env bash
# Fails a build that asks for both test mode and demo mode.
#
# Test mode feeds the camera screens recorded frames so they can run on an emulator.
# Demo mode is for showing the product to people. A build that was both would present
# recorded detections as live ones, and nobody watching could tell.
#
# Reads TEST_MODE and DEMO_MODE from the environment.
# Exit: 0 the combination is allowed, 1 it is not.
set -euo pipefail

test_mode="${TEST_MODE:-false}"
demo_mode="${DEMO_MODE:-false}"

is_enabled() {
  case "$1" in
    1|true|TRUE|yes|YES) return 0 ;;
    0|false|FALSE|no|NO|'') return 1 ;;
    *) echo "FAIL: invalid build-mode value: $1" >&2; exit 1 ;;
  esac
}

if is_enabled "$test_mode" && is_enabled "$demo_mode"; then
  echo "FAIL: TEST_MODE and DEMO_MODE cannot both be enabled." >&2
  echo "      Test mode replays recorded frames; a demo build would show them as real." >&2
  exit 1
fi

echo "PASS: build modes are allowed (test_mode=$test_mode demo_mode=$demo_mode)"
