SHELL := /bin/bash
export PATH := $(HOME)/.local/bin:$(PATH)

PY_DIRS := apps/backend apps/ml-service ml scripts migrations e2e conftest.py
MYPY_ML_DIR := apps/ml-service
MYPY_ML_ADAPTER_ROOTS := ml/forecast ml/backtest
PY_FILES := $(shell scripts/has-py-files.sh $(PY_DIRS))
# mypy errors on a directory with no .py files, so pass only populated ones.
# The ML implementation and public adapters are separate invocations: the
# former contains the existing vision namespace and the latter contains the
# issue-compatible `ml` scripts, which must not be discovered as duplicates.
MYPY_DIRS := $(shell for d in $(filter-out $(MYPY_ML_DIR) ml,$(PY_DIRS)); do [ -n "$$(scripts/has-py-files.sh $$d)" ] && printf '%s ' "$$d"; done)
MYPY_ML_IMPL_DIRS := $(shell for d in apps/ml-service/vision apps/ml-service/src/farmable_ml; do [ -n "$$(scripts/has-py-files.sh $$d)" ] && printf '%s ' "$${d#apps/ml-service/}"; done)
MYPY_ML_ADAPTER_DIRS := $(shell for d in $(MYPY_ML_ADAPTER_ROOTS); do [ -n "$$(scripts/has-py-files.sh $$d)" ] && printf '%s ' "$$d"; done)
PY_TEST_FILES := $(shell find apps/backend -name 'test_*.py' -o -name '*_test.py' 2>/dev/null)
SCRIPT_TEST_FILES := $(shell find scripts/tests -name 'test_*.py' 2>/dev/null)
ML_SERVICE_TEST_FILES := $(shell find apps/ml-service -name 'test_*.py' -o -name '*_test.py' 2>/dev/null)
ML_ADAPTER_TEST_FILES := $(shell find $(MYPY_ML_ADAPTER_ROOTS) -name 'test_*.py' -o -name '*_test.py' 2>/dev/null)

.PHONY: setup lint format typecheck test test-integration hooks check-no-raw-sql client db-migrate queue-schema
.PHONY: client-check security-audit migration-safety deployability e2e-api e2e-degradation e2e-mobile mobile-test-build
.PHONY: smoke smoke-voice mobile-checks demo-regression

smoke:
	uv run python -m farmable_backend.integrations.smoke $(SMOKE_ARGS)

smoke-voice:
	uv run python scripts/smoke_gemini_live.py $(SMOKE_ARGS)

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
	@if [ -n "$(MYPY_ML_IMPL_DIRS)" ]; then (cd $(MYPY_ML_DIR) && MYPYPATH=src uv run mypy --explicit-package-bases --ignore-missing-imports $(MYPY_ML_IMPL_DIRS)); fi
	@if [ -n "$(MYPY_ML_ADAPTER_DIRS)" ]; then uv run mypy --explicit-package-bases --ignore-missing-imports $(MYPY_ML_ADAPTER_DIRS); fi
	pnpm -r --if-present run typecheck

test:
	@if [ -n "$(SCRIPT_TEST_FILES)" ]; then uv run pytest scripts/tests -q; fi
	@if [ -n "$(PY_TEST_FILES)" ]; then uv run pytest apps/backend; else echo "no backend tests yet, skipping pytest"; fi
	@if [ -n "$(ML_SERVICE_TEST_FILES)" ]; then uv run pytest apps/ml-service; else echo "no ML service tests yet, skipping pytest"; fi
	@if [ -n "$(ML_ADAPTER_TEST_FILES)" ]; then uv run pytest $(MYPY_ML_ADAPTER_ROOTS); else echo "no ML adapter tests yet, skipping pytest"; fi
	pnpm -r --if-present run test

check-no-raw-sql:
	@scripts/check-no-raw-sql.sh

client:
	uv run python scripts/generate_client.py

# Explicitly run after migrations. No fixture directory is scanned by default.
FORECAST_DIR ?= ml/forecast/results
.PHONY: forecast-import-latest forecast-activate
forecast-import-latest:
	uv run python -m farmable_backend.forecast_cli import-latest --root "$(FORECAST_DIR)"

forecast-activate:
	uv run python -m farmable_backend.forecast_cli activate --run "$(RUN)"

client-check: client
	@git diff --exit-code -- packages/api-client || { echo 'client-stale: run make client and commit its output'; exit 1; }

security-audit:
	uv run python scripts/audit_dependencies.py

migration-safety:
	uv run python scripts/migration_safety.py

deployability e2e-api e2e-degradation:
	@bash scripts/ci-stack.sh $@

mobile-test-build:
	@bash scripts/ci-mobile.sh build

e2e-mobile:
	@APK="$(APK)" bash scripts/ci-mobile.sh test

test-integration:
	@bash scripts/test-integration.sh

db-migrate:
	uv run alembic upgrade head

queue-schema:
	uv run python -m farmable_backend.manage queue-schema

mobile-checks:
	node --test scripts/tests/mobile-api.test.mjs
	bash scripts/check-test-mode.sh
	cd apps/mobile && flutter pub get --enforce-lockfile
	cd apps/mobile && dart run tool/generate_tokens.dart --verify
	cd apps/mobile && dart format --output=none --set-exit-if-changed .
	cd apps/mobile && flutter analyze
	cd apps/mobile && flutter test --exclude-tags demo-api
	cd apps/mobile && flutter test --plain-name 'renders the farm with no network and no spinner' test/home_screen_test.dart
	uv run python scripts/test_mobile_contract.py

demo-regression:
	uv run python -m farmable_backend.demo_api.rehearse
	uv run pytest apps/backend/tests/test_demo_planner.py apps/backend/tests/test_demo_api.py -q
