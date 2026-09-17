# AGENTS.md

Instructions for anyone — human or agent — working in this repository.

## Setup

```
git clone https://github.com/ctrl-alt-elite-za/Farmable.git
cd Farmable
make setup
```

`make setup` installs `uv` if missing, syncs Python dependencies (`uv sync`),
enables Corepack (installing its shims into `$HOME/.local/bin`, so it never
needs write access to a system-owned Node directory), installs Node
dependencies (`pnpm install`), and installs the git hooks. Make sure
`$HOME/.local/bin` is on your `PATH` — see the README for details. It works on Windows via WSL, macOS and Linux from a fresh
clone. Tool versions are pinned in `.python-version`, `.nvmrc`,
`package.json`'s `packageManager`, and `.pre-commit-config.yaml`.

## Commands

| Command                 | Does                                                                          |
| ----------------------- | ----------------------------------------------------------------------------- |
| `make setup`            | One-time (and repeatable) environment setup                                   |
| `make lint`             | Ruff, ESLint                                                                  |
| `make format`           | Ruff format, Prettier — applies fixes                                         |
| `make typecheck`        | mypy, TypeScript project references                                           |
| `make test`             | pytest (`scripts/tests`, `apps/backend`), workspace test scripts              |
| `make hooks`            | (Re-)installs the pre-commit and pre-push git hooks                           |
| `make check-no-raw-sql` | Fails if `apps/backend/`/`migrations/` contain hand-written SQL               |
| `make client`           | Regenerates `packages/api-client` from FastAPI; no database connection needed |
| `make test-integration` | Exercises API + worker + PostGIS in an isolated disposable Compose project    |
| `make db-migrate`       | Applies Alembic migrations explicitly; never run migrations on API startup    |
| `make queue-schema`     | Installs Procrastinate's vendor schema once on a new database                 |

Each command is a no-op (and exits 0) for a language that has no source
files yet, so they all pass on the empty skeleton and keep working as `#3`
and `#4` add code.

## Conventions

- **Monorepo layout:** `apps/backend/` (Python API + worker), `apps/mobile/`
  (Expo app), `apps/ml-service/` (forecast/backtest),
  `packages/api-client/` (generated, never hand-edited),
  `packages/geo/` (pure TS geometry library),
  `infra/` (deploy config), `e2e/` (end-to-end tests), `docs/decisions/`
  (ADRs).
- **Database access only through the SQLAlchemy ORM — never hand-written
  SQL.** No `text()`, no SQL strings passed to `execute()`, no Alembic
  `op.execute()`, no raw cursors. Three checks enforce this, deliberately
  overlapping: ruff's `TID251` bans every route reachable through an import —
  `sqlalchemy.text` and its aliases, and the DBAPI drivers (`sqlite3`,
  `psycopg`, `psycopg2`) — which needs no SQL recognition and so cannot be
  defeated by formatting or dialect;
  ruff's `S608` catches query strings built by interpolation; and
  `make check-no-raw-sql` parses the AST for what neither can see — methods
  called on a runtime object, such as `cursor.execute("SELECT ...")`. A single
  false positive can be waived in place with a `# raw-sql: allow` comment (or
  `# noqa: TID251` for the import rule). There is deliberately no way to switch
  the check off from inside a file; a file that genuinely cannot be parsed goes
  in `[tool.check-no-raw-sql] exclude` in `pyproject.toml`, where taking code
  out of the guardrail shows up in review. A clean run reports how many files
  it examined, and refuses to report at all if any file was neither analysed
  nor excluded. The AST check runs automatically on
  `git push` whenever `apps/backend/` or
  `migrations/` changed (see `scripts/changed-scopes.sh`), and becomes a
  required CI check on `main` in #5.
- Formatting and simple lint issues are auto-fixed on commit (pre-commit
  hooks) and, if any slip through, on the PR itself (autofix.ci) — never
  hand-format to match a linter.
- Commits should be small and pass `make lint && make typecheck` locally
  before pushing; the pre-push hook checks only the folders you changed.

## Secrets

- **Never commit secrets.** `.env*` (except `.env.example`) and key/cert
  files are gitignored; gitleaks blocks them at commit time and in CI, and
  GitHub push protection blocks them at push time.
- If a secret is ever committed anyway: removing it from the latest commit
  is not enough (git history keeps it) — treat it as compromised, rotate it
  immediately, then clean history.
- Copy `.env.example` to `.env` and fill in real values locally; `.env` is
  never read in CI or committed anywhere.

## Definition of Done

- Each issue's **acceptance criteria** (in its GitHub issue body) are the
  definition of done for that issue — not "it looks right", not "tests pass
  locally". If a criterion can't be met, say so and why, rather than
  marking the issue done.
- `make lint`, `make typecheck` and `make test` exit 0.
- New backend behavior has tests; new endpoints follow the safe defaults
  in #3 (error format, request IDs, log masking, rate limits, strict
  request validation).
