#!/usr/bin/env bash
# Prints a non-empty string and exits 0 iff any given directory has a .py
# file. Usage: scripts/has-py-files.sh apps/backend apps/ml-service
set -uo pipefail # no -e: avoids SIGPIPE failure when `head` closes early
found="$(find "$@" -name '*.py' 2>/dev/null | head -1)"
[ -n "$found" ] && echo "$found"
