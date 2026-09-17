#!/usr/bin/env bash
# Checks that the connected Android test phone can run ARCore, which the AR mapping
# features (#15, #18) need.
#
# Google publishes the supported-device list as an HTML page with no machine-readable
# feed, so this asks the phone instead: ARCore ships as the app com.google.ar.core, and
# Google Play only offers it on devices from that list.
#
# Usage: scripts/check-arcore-device.sh [--help]
# Exit:  0 supported, 1 not supported, 2 could not check (no adb, or no device attached).
set -euo pipefail

if [ "${1:-}" = "--help" ]; then
  sed -n '2,12p' "$0"
  exit 0
fi

if ! command -v adb >/dev/null 2>&1; then
  echo "SKIP: adb not found - install Android platform-tools and attach the phone" >&2
  exit 2
fi

model="$(adb shell getprop ro.product.model 2>/dev/null | tr -d '\r' || true)"
if [ -z "$model" ]; then
  echo "SKIP: no Android device is attached (check 'adb devices')" >&2
  exit 2
fi

if adb shell pm list packages 2>/dev/null | tr -d '\r' | grep -qx 'package:com.google.ar.core'; then
  echo "PASS: $model has ARCore (com.google.ar.core) installed"
  exit 0
fi

echo "FAIL: $model does not have ARCore installed." >&2
echo "      Check https://developers.google.com/ar/devices and install" >&2
echo "      'Google Play Services for AR' from the Play Store." >&2
exit 1
