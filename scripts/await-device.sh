#!/usr/bin/env bash
# Wait until an Android emulator can actually answer adb, or fail.
#
# Maestro drives the device over adb. Stopping the API mid-run has dropped
# that connection: the offline flow then died with
# "Command failed (tcp:NNNNN): closed" before executing a single command,
# while a screenshot taken at the same moment showed the app running fine.
# That reads as a product failure when nothing is wrong with the product,
# which is the worst kind of flake — a red e2e that is usually a lie teaches
# the team to stop reading it.
#
# Every wait here is bounded, including the ones that look instantaneous:
#
#   * `adb wait-for-device` blocks forever by default. A deadline around the
#     polling loop alone never fires, because control never reaches the loop.
#   * `adb shell` can hang on a half-dead connection rather than erroring, so
#     a single probe can outlive the whole budget.
#
# Exit 0 once the device reports a completed boot, 1 on the deadline.
#
# Lives in its own file so scripts/tests/test_await_device.py can drive it
# against stub adb binaries. That test exists because the first version of
# this helper shipped with `tr -d ''` instead of `tr -d ''` — adb returns
# "1\r", the comparison never matched, and the helper would have failed every
# run. Reading the script did not catch it; running it does.
set -euo pipefail

TIMEOUT_SECONDS="${AWAIT_DEVICE_TIMEOUT:-60}"
PROBE_TIMEOUT="${AWAIT_DEVICE_PROBE_TIMEOUT:-10}"

deadline=$((SECONDS + TIMEOUT_SECONDS))

remaining() {
  local left=$((deadline - SECONDS))
  [ "$left" -gt 0 ] && echo "$left" || echo 0
}

# Never let the initial connect consume the whole budget on its own.
initial=$(remaining)
if [ "$initial" -gt 0 ]; then
  timeout "$initial" adb wait-for-device || true
fi

while [ "$SECONDS" -lt "$deadline" ]; do
  probe=$(remaining)
  [ "$probe" -gt "$PROBE_TIMEOUT" ] && probe="$PROBE_TIMEOUT"
  # adb prints "1\r" on Android; the carriage return must go or the
  # comparison silently never matches.
  booted=$(timeout "$probe" adb shell getprop sys.boot_completed 2>/dev/null | tr -d '\r' || true)
  if [ "$booted" = "1" ]; then
    exit 0
  fi
  sleep 1
done

echo "await-device: emulator did not answer adb within ${TIMEOUT_SECONDS}s" >&2
exit 1
