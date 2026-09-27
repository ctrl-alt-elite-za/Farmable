# Local fallback demo

A backup for the demo if staging isn't ready: the backend runs on a laptop
with **fake integrations**, and Thandi's account is seeded with a lived-in farm.
Local use only: never point any of this at staging or production.

- Sign-up codes are fixed: **111111** (phone) and **222222** (email).
- The typed assistant answers with the scripted fake model. Voice needs real
  Gemini Live, so it does not work locally.
- Demo login after seeding: `thandi.demo@example.com` / `three blind field mice`.

## 1. Run the backend

Either:

- **These scripts** (Linux or WSL with PostgreSQL 14+ installed; no Docker needed):

  ```bash
  bash scripts/local-demo/start.sh      # PostgreSQL on 5433, API on 127.0.0.1:8000, worker
  bash scripts/local-demo/stop.sh       # stops them; data is kept in ~/.farmable-local
  bash scripts/local-demo/reset.sh      # wipes the local database back to empty
  ```

  If PostgreSQL's binaries aren't in `/usr/lib/postgresql/14/bin`, set `PG_BIN`.

- **Or Docker Compose,** with the same settings the CI mobile stack uses:
  `ENVIRONMENT=ci INTEGRATIONS_MODE=fake API_PORT=8000` plus the variables in
  `scripts/local-demo/env.sh`. See `scripts/ci-stack.sh` for the full start-up
  order (migrate, queue-schema, api, worker).

## 2. Seed Thandi's account

```bash
UV_PYTHON=3.12 uv run python scripts/local-demo/seed_demo_account.py
```

Safe to run again: records have fixed ids, so nothing is duplicated. It
refuses any API that isn't `localhost` / `127.0.0.1`.

Seeded: Thandi Farm, 4 sections (Cabbage Field already walked and mapped near
KwaMashu, North Plot empty), 3 plantings, 5 tasks (weeding 4 days overdue),
3 health checks (leaf curl on the tomatoes needs a look), and 5 money records.
Harvest windows and projected profit appear once a plan is confirmed on the
phone. That's a demo step.

## 3. Run the app from Android Studio

The app allows plain `http` only to `localhost` / `127.0.0.1` / `10.0.2.2`, so:

- **Emulator:** run with
  `--dart-define=API_URL=http://10.0.2.2:8000 --dart-define=TEST_MODE=false --dart-define=DEMO_MODE=false`
- **Real Android phone on USB:** run `adb reverse tcp:8000 tcp:8000`, then run with
  `--dart-define=API_URL=http://localhost:8000 --dart-define=TEST_MODE=false --dart-define=DEMO_MODE=false`

In Android Studio, put the `--dart-define` flags in the run configuration's
**Additional run args**. An iPhone can't reach `http` on the laptop, so use Android.

Then **Log in** with the demo account above. Don't use "Try the demo farm":
that's the built-in offline farm, not this account.
