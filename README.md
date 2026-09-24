# Farmable

This is a decision-support app that solves smallholder farmer income loss using live market prices, weather forecasts, and input costs.

## Setup

One command, from a fresh clone:

```bash
git clone https://github.com/ctrl-alt-elite-za/Farmable.git
cd Farmable
make setup
```

### Prerequisites

- **Node** — the version in [`.nvmrc`](.nvmrc) (Node 22). `nvm install` picks it up
  automatically. pnpm itself is provisioned by Corepack; don't install it globally.
- **Python** — the version in [`.python-version`](.python-version) (3.12). `uv` is
  installed by `make setup` if it is missing, and manages the virtualenv.
- **`$HOME/.local/bin` on your `PATH`** — `make setup` installs the Corepack shims
  (`pnpm`) and `uv` there. Add this to your shell profile:

  ```bash
  export PATH="$HOME/.local/bin:$PATH"
  ```

Works on Linux, macOS, and Windows via WSL.

### What `make setup` does

1. Installs `uv` if it is missing.
2. Enables Corepack, installing its shims into `$HOME/.local/bin` so it never
   needs write access to the system Node directory.
3. Syncs Python dependencies (`uv sync`) and Node dependencies
   (`pnpm install --frozen-lockfile`) in parallel.
4. Installs the git pre-commit and pre-push hooks.

Tool versions are pinned in `.python-version`, `.nvmrc`, `package.json`'s
`packageManager` and `devDependencies`, `uv.lock`, `pnpm-lock.yaml`, and
`.pre-commit-config.yaml`.

## Commands

| Command                 | Does                                                                    |
| ----------------------- | ----------------------------------------------------------------------- |
| `make setup`            | One-time (and repeatable) environment setup                             |
| `make lint`             | Ruff, ESLint                                                            |
| `make format`           | Ruff format, Prettier — applies fixes                                   |
| `make typecheck`        | mypy, TypeScript project references                                     |
| `make test`             | pytest (`scripts/tests`, `apps/backend`), workspace test scripts        |
| `make hooks`            | (Re-)installs the pre-commit and pre-push git hooks                     |
| `make check-no-raw-sql` | Fails if `apps/backend/`/`migrations/` contain hand-written SQL         |
| `make client`           | Regenerates the typed API client from FastAPI's OpenAPI schema          |
| `make test-integration` | Tests API + worker + PostGIS in an isolated, disposable Compose project |
| `make db-migrate`       | Explicitly applies Alembic migrations using environment credentials     |
| `make queue-schema`     | Installs Procrastinate's vendor schema once on a new database           |

See [the backend guide](apps/backend/README.md) for local services, safe defaults,
migrations, and integration tests. Unit tests do not require Docker. Commands for
languages with no source files yet remain no-ops.

## Email delivery (Gmail SMTP)

Live OTP/notification email (issue #9) sends through Gmail SMTP behind a
provider-agnostic `EmailSender` interface
(`apps/backend/src/farmable_backend/integrations/email/`). See
[docs/services.md](docs/services.md) for the full reliability/config table;
Twilio SMS is unchanged (see the same doc).

**Create a Gmail App Password** (required — the account password won't work):

1. Enable 2-Step Verification on the sending Gmail account.
2. Go to Google Account → Security → App passwords, create one for "Mail",
   and copy the 16-character password (no spaces).

**Required environment variables** (see `.env.example`):

| Variable             | Meaning                                                        |
| -------------------- | -------------------------------------------------------------- |
| `SMTP_HOST`          | `smtp.gmail.com`                                               |
| `SMTP_PORT`          | `587` (STARTTLS, default) or `465` (SSL)                       |
| `SMTP_TLS_MODE`      | `starttls` or `ssl`, matching the port                         |
| `SMTP_USER`          | The Gmail address that sends, e.g. `noreply.almanac@gmail.com` |
| `SMTP_PASSWORD`      | The 16-character App Password, never the account password      |
| `EMAIL_FROM_NAME`    | Display name shown to recipients, e.g. `Almanac`               |
| `EMAIL_FROM_ADDRESS` | Sender address shown to recipients                             |

All are required when `INTEGRATIONS_MODE=live`; `GmailSmtpEmailSender` raises
immediately at construction if any are missing, rather than failing on the
first send. Outbound port 25 is blocked on Google Cloud (Cloud Run/Compute
Engine/App Engine); 587 and 465 both work, which is why 587/STARTTLS is the
default.

**Run the manual test-send script** once configuration is in place:

```bash
uv run python scripts/send_test_email.py you@example.com
```

Prints `PASS`/`FAIL`; never run this in CI or any automated check — it sends
one real email and, on a Gmail trial-limited sending domain, consumes part of
Gmail's roughly 500-emails/day account limit.

**Switching providers later**: implement `EmailSender.send(to, subject, html,
text) -> bool` in a new class under `integrations/email/`, then construct it
instead of `GmailSmtpEmailSender` where `LiveOtpProvider` is built (currently
`main.py`'s lifespan). No other code changes.

## Troubleshooting

**`corepack enable` fails with `EACCES`.** Plain `corepack enable` writes its
shims next to the installed Node binary, which is root-owned on Ubuntu and WSL.
`make setup` avoids this by passing `--install-directory "$HOME/.local/bin"`.
If you run Corepack by hand, do the same:

```bash
mkdir -p "$HOME/.local/bin"
corepack enable --install-directory "$HOME/.local/bin"
```

**`pnpm: command not found` after setup.** `$HOME/.local/bin` is not on your
`PATH` — see Prerequisites above.

**Hooks reformat files differently from CI.** Prettier is pinned to a single
exact version in `package.json` and resolved through `pnpm-lock.yaml`; the
pre-commit hook runs that same binary via `pnpm exec`. Run `make setup` to
re-sync if you see drift.

## Conventions

See [AGENTS.md](AGENTS.md) for repository conventions, secret handling, and the
definition of done. Notably: **all database access goes through the SQLAlchemy
ORM — never hand-written SQL.** `make check-no-raw-sql` parses the Python AST to
enforce this and runs automatically on `git push`.

Pull-request workflows, local reproduction commands, migration approvals,
safe failure reports and remaining activation dependencies are documented in
[docs/ci.md](docs/ci.md).
