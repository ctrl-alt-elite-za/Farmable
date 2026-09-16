#!/usr/bin/env bash
# Prints a non-empty string (and exits 0) iff any of the given directories
# contain a .py file; otherwise prints nothing and exits 1. Used everywhere
# a Python tool (ruff, mypy) needs to be skipped until the Python apps exist.
# Usage: scripts/has-py-files.sh apps/backend apps/ml-service
set -uo pipefail
# `pipefail` would make this fail on SIGPIPE when `head` closes the pipe
# early, so pipefail is intentionally not paired with `set -e` here.
found="$(find "$@" -name '*.py' 2>/dev/null | head -1)"
[ -n "$found" ] && echo "$found"
