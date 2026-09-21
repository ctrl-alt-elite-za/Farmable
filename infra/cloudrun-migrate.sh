#!/usr/bin/env bash
set -Eeuo pipefail

# Application migrations and the Procrastinate vendor schema are both required
# before the API/worker revision can satisfy its readiness contract.
uv run alembic upgrade head
uv run python -m farmable_backend.manage queue-schema
