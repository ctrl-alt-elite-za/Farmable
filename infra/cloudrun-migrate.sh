#!/usr/bin/env bash
set -Eeuo pipefail

# Application migrations and the Procrastinate vendor schema are both required
# before the API/worker revision can satisfy its readiness contract.
# Call the binaries directly. `uv run` re-syncs the project before executing, which
# needs write access to /app/.venv -- created by root in the image's base stage while
# this job runs as `farmable`. /app/.venv/bin is already on PATH.
alembic upgrade head
python -m farmable_backend.manage queue-schema
