#!/usr/bin/env bash
# Fails a build that asks for both test mode and demo mode.
#
# Test mode feeds the camera screens recorded frames so they can run on an emulator.
# Demo mode is for showing the product to people. A build that was both would present
# recorded detections as live ones, and nobody watching could tell.
#
# Reads EXPO_PUBLIC_TEST_MODE and EXPO_PUBLIC_DEMO_MODE from the environment.
# Exit: 0 the combination is allowed, 1 it is not.
set -euo pipefail

test_mode="${EXPO_PUBLIC_TEST_MODE:-0}"
demo_mode="${EXPO_PUBLIC_DEMO_MODE:-0}"

if [ "$test_mode" = "1" ] && [ "$demo_mode" = "1" ]; then
  echo "FAIL: EXPO_PUBLIC_TEST_MODE=1 and EXPO_PUBLIC_DEMO_MODE=1 cannot both be set." >&2
  echo "      Test mode replays recorded frames; a demo build would show them as real." >&2
  exit 1
fi

echo "PASS: build modes are allowed (test_mode=$test_mode demo_mode=$demo_mode)"
