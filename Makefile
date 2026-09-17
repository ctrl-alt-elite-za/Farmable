SHELL := /bin/bash
export PATH := $(HOME)/.local/bin:$(PATH)

PY_DIRS := apps/backend apps/ml-service scripts migrations
PY_FILES := $(shell scripts/has-py-files.sh $(PY_DIRS))
# mypy errors on a directory with no .py files, so pass only populated ones.
MYPY_DIRS := $(shell for d in apps/backend scripts; do [ -n "$$(scripts/has-py-files.sh $$d)" ] && printf '%s ' "$$d"; done)
MYPY_ML_DIR := apps/ml-service
PY_TEST_FILES := $(shell find apps/backend -name 'test_*.py' -o -name '*_test.py' 2>/dev/null)
SCRIPT_TEST_FILES := $(shell find scripts/tests -name 'test_*.py' 2>/dev/null)

.PHONY: setup lint format typecheck test test-integration hooks check-no-raw-sql client db-migrate queue-schema

setup:
	@command -v uv >/dev/null 2>&1 || { echo "Installing uv..."; curl -LsSf https://astral.sh/uv/install.sh | sh; }
	@command -v corepack >/dev/null 2>&1 || { echo "corepack not found - install Node $$(cat .nvmrc) first (see README)"; exit 1; }
	@# Install the Corepack shims into a user-writable dir: plain `corepack enable`
	@# writes beside the Node binary, which is EACCES on system-owned Node.
	@mkdir -p $(HOME)/.local/bin
	@corepack enable --install-directory "$(HOME)/.local/bin" \
		|| corepack enable \
		|| { echo "corepack enable failed - see README troubleshooting"; exit 1; }
	@command -v pnpm >/dev/null 2>&1 || { \
		echo "pnpm not on PATH after corepack enable."; \
		echo "Add this to your shell profile: export PATH=\"$$HOME/.local/bin:$$PATH\""; \
		exit 1; }
	@# uv and pnpm install in parallel; each exit code is checked explicitly.
	@set -e; \
	(uv sync) & uv_pid=$$!; \
	(pnpm install --frozen-lockfile || pnpm install) & pnpm_pid=$$!; \
	uv_status=0; pnpm_status=0; \
	wait $$uv_pid || uv_status=$$?; \
	wait $$pnpm_pid || pnpm_status=$$?; \
	[ $$uv_status -eq 0 ] || { echo "uv sync failed" >&2; exit $$uv_status; }; \
	[ $$pnpm_status -eq 0 ] || { echo "pnpm install failed" >&2; exit $$pnpm_status; }
	$(MAKE) hooks
	@echo "Setup complete."

hooks:
	@uv run pre-commit install-hooks
	@# scripts/hooks/pre-commit wraps pre-commit to re-add autofixed files.
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
	@if [ -n "$(PY_FILES)" ]; then uv run mypy $(MYPY_DIRS); else echo "no Python files yet, skipping mypy"; fi
	@if [ -n "$(shell scripts/has-py-files.sh $(MYPY_ML_DIR))" ]; then (cd $(MYPY_ML_DIR) && uv run mypy --explicit-package-bases --ignore-missing-imports vision); fi
	pnpm -r --if-present run typecheck

test:
	@if [ -n "$(SCRIPT_TEST_FILES)" ]; then uv run pytest scripts/tests -q; fi
	@if [ -n "$(PY_TEST_FILES)" ]; then uv run pytest apps/backend; else echo "no backend tests yet, skipping pytest"; fi
	pnpm -r --if-present run test

check-no-raw-sql:
	@scripts/check-no-raw-sql.sh

client:
	uv run python scripts/generate_client.py

test-integration:
	@bash scripts/test-integration.sh

db-migrate:
	uv run alembic upgrade head

queue-schema:
	uv run python -m farmable_backend.manage queue-schema
