# AGENTS.md

Instructions for anyone — human or agent — working in this repository.

## Setup

```
git clone https://github.com/ctrl-alt-elite-za/Farmable.git
cd Farmable
make setup
```

`make setup` installs `uv` if missing, syncs Python dependencies (`uv sync`),
enables Corepack, installs Node dependencies (`pnpm install`), and installs
the git hooks. It works on Windows via WSL, macOS and Linux from a fresh
clone. Tool versions are pinned in `.python-version`, `.nvmrc`,
`package.json`'s `packageManager`, and `.pre-commit-config.yaml`.

## Commands

| Command                 | Does                                                                                 |
| ----------------------- | ------------------------------------------------------------------------------------ |
| `make setup`            | One-time (and repeatable) environment setup                                          |
| `make lint`             | Ruff, ESLint                                                                         |
| `make format`           | Ruff format, Prettier — applies fixes                                                |
| `make typecheck`        | mypy, TypeScript project references                                                  |
| `make test`             | pytest (apps/backend), workspace test scripts                                        |
| `make hooks`            | (Re-)installs the pre-commit and pre-push git hooks                                  |
| `make check-no-raw-sql` | Fails if `apps/backend/`/`migrations/` contain hand-written SQL                      |
| `make client`           | Regenerates `packages/api-client` from `apps/backend`'s OpenAPI schema (added in #3) |

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
  `op.execute()`, no raw cursors. `make check-no-raw-sql` enforces this —
  it runs automatically on `git push` whenever `apps/backend/` or
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
