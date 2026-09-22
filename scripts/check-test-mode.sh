#!/usr/bin/env bash
# Fails a build that asks for both test mode and demo mode.
#
# Test mode feeds the camera screens recorded frames so they can run on an emulator.
# Demo mode is for showing the product to people. A build that was both would present
# recorded detections as live ones, and nobody watching could tell.
#
# Reads TEST_MODE and DEMO_MODE from the environment, and the build must be given the
# same values as --dart-define. There is no second source of truth: a --dart-define is
# a compiler flag this script cannot see, so anything that only sets the define leaves
# the guard reading defaults and passing whatever it is handed.
#
# The spelling is `true`/`false` because that is the only thing Dart's
# bool.fromEnvironment recognises. Anything else is rejected rather than read as
# false, so a stray TEST_MODE=1 fails loudly here instead of compiling into a build
# that quietly is not in test mode.
#
# Exit: 0 the combination is allowed, 1 it is not.
set -euo pipefail

test_mode="${TEST_MODE:-false}"
demo_mode="${DEMO_MODE:-false}"

for pair in "TEST_MODE=$test_mode" "DEMO_MODE=$demo_mode"; do
  value="${pair#*=}"
  if [ "$value" != "true" ] && [ "$value" != "false" ]; then
    echo "FAIL: ${pair%%=*} must be exactly 'true' or 'false', got '$value'." >&2
    echo "      Dart's bool.fromEnvironment reads nothing else, so any other" >&2
    echo "      spelling compiles as false while reading as set here." >&2
    exit 1
  fi
done

if [ "$test_mode" = "true" ] && [ "$demo_mode" = "true" ]; then
  echo "FAIL: TEST_MODE=true and DEMO_MODE=true cannot both be set." >&2
  echo "      Test mode replays recorded frames; a demo build would show them as real." >&2
  exit 1
fi

echo "PASS: build modes are allowed (test_mode=$test_mode demo_mode=$demo_mode)"
