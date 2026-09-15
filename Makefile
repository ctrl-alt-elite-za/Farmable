SHELL := /bin/bash
export PATH := $(HOME)/.local/bin:$(PATH)

# Set once so every target's "skip if no Python files yet" guard shares one
# tree walk instead of each target re-running find. Recomputed on every
# invocation (not cached to a file) since Make re-evaluates := at parse time,
# which is exactly once per `make` run.
PY_FILES := $(shell find backend ml -name '*.py' 2>/dev/null)
PY_TEST_FILES := $(shell find backend -name 'test_*.py' -o -name '*_test.py' 2>/dev/null)

.PHONY: setup lint format typecheck test hooks check-no-raw-sql client

setup:
	@command -v uv >/dev/null 2>&1 || { echo "Installing uv..."; curl -LsSf https://astral.sh/uv/install.sh | sh; }
	@command -v corepack >/dev/null 2>&1 || { echo "corepack not found - install Node $$(cat .nvmrc) first (see README)"; exit 1; }
	@corepack enable
	@# uv and pnpm are independent package managers; install in parallel.
	@(uv sync) & (pnpm install --frozen-lockfile || pnpm install) & wait
	$(MAKE) hooks
	@echo "Setup complete."

hooks:
	@uv run pre-commit install-hooks
	@# pre-commit's own pre-commit hook aborts a commit when a hook edits a
	@# file instead of re-adding it; scripts/hooks/pre-commit wraps it so a
	@# commit with autofixed formatting still succeeds (see #2). The pre-push
	@# hook uses plain `pre-commit install` since push has no "re-add" step.
	@install -m 755 scripts/hooks/pre-commit .git/hooks/pre-commit
	@uv run pre-commit install --hook-type pre-push -f

lint:
	@if [ -n "$(PY_FILES)" ]; then uv run ruff check .; else echo "no Python files yet, skipping ruff"; fi
	pnpm -r --if-present run lint
	@if [ -f eslint.config.mjs ]; then pnpm exec eslint . --max-warnings=0; fi

format:
	@if [ -n "$(PY_FILES)" ]; then uv run ruff format .; fi
	pnpm exec prettier --write .

typecheck:
	@if [ -n "$(PY_FILES)" ]; then uv run mypy backend ml; else echo "no Python files yet, skipping mypy"; fi
	pnpm -r --if-present run typecheck

test:
	@if [ -n "$(PY_TEST_FILES)" ]; then uv run pytest backend; else echo "no backend tests yet, skipping pytest"; fi
	pnpm -r --if-present run test

check-no-raw-sql:
	@scripts/check-no-raw-sql.sh

client:
	@echo "make client is implemented in #3 once the backend's OpenAPI schema exists."
