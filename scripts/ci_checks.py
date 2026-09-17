"""Fixed CI commands and safe diagnostic vocabulary (also used by the trusted reporter)."""

CHECKS = {
    "scopes": ("python scripts/ci_scopes.py --base origin/main", "Fetch a valid base commit."),
    "lint": ("make lint", "Fix style errors with make format and pnpm exec eslint . --fix."),
    "typecheck": ("make typecheck", "Correct the reported Python or TypeScript types."),
    "unit-tests": ("make test", "Fix the failing assertion; do not retry failing tests."),
    "integration-tests": ("make test-integration", "Start Docker, then reproduce locally."),
    "client-up-to-date": ("make client-check", "Run make client and commit packages/api-client."),
    "no-raw-sql": ("make check-no-raw-sql", "Replace application-written SQL with ORM calls."),
    "security-audit": ("make security-audit", "Upgrade the vulnerable dependency and lockfile."),
    "migration-safety": (
        "make migration-safety CI_BASE=<base-sha>",
        "Replace dangerous operations or obtain the maintainer-only migration-approved label.",
    ),
    "deployability": (
        "make deployability",
        "Fix the image, migration, worker, or readiness failure.",
    ),
    "e2e-api": ("make e2e-api", "Fix the API contract against the running Docker stack."),
    "e2e-degradation": ("make e2e-degradation", "Fix readiness/liveness under dependency failure."),
    "e2e-mobile": ("make e2e-mobile APK=<test-apk>", "Build #4's test-mode APK and run Maestro."),
    "assistant-evals": (
        "make eval-assistant SET=dev",
        "Fix the assistant development evaluations; never tune against held-back cases.",
    ),
    "gitleaks": (
        "gitleaks git --redact",
        "Remove the secret from the commit/history AND rotate it; deletion alone is insufficient.",
    ),
    "codeql": ("See the CodeQL job's analysis", "Resolve the code-scanning finding."),
    "autofix": ("make format && make client", "Apply and commit mechanical changes."),
}

DIAGNOSTICS = {
    "type-error": "Compiler/type-check error (error details stay in the read-only job logs).",
    "lint-error": "Style diagnostic from Ruff or ESLint.",
    "test-failed": "A test failed; test failures are not retried.",
    "drop-column": "ALTER TABLE [table] DROP COLUMN [column]; requires migration-approved.",
    "drop-table": "DROP TABLE [identifier]; requires migration-approved.",
    "migration-danger": "Squawk flagged a dangerous migration; requires migration-approved.",
    "audit-high": "A high/critical dependency vulnerability was found.",
    "audit-unknown": "A scanner or severity lookup failed; the audit failed closed.",
    "client-stale": "Generated client differs from the committed API contract.",
    "prerequisite": "A prerequisite is unavailable; see the dependency issue.",
    "timeout": "The command exceeded its time limit.",
}

# The workflow execution and GitHub Advanced Security findings are different checks.
CHECKS["CodeQL"] = CHECKS["codeql"]
