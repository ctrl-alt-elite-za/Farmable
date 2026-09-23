# Issue #9 acceptance matrix (working record)

Worktree: `C:\Users\User\Desktop\Geekulcha\Farmable-resolve-issue-9-final`
Branch: `resolve-issue/9-complete-backend-identity`
Base: `origin/main` @ `576b7aa`
PR #44 and PR #65 both merged into main already (confirmed via `gh pr view`).

## Verified findings (read directly from origin/main source, not assumed)

- `apps/backend/src/farmable_backend/auth.py` — signup/verify/login/refresh live here.
- `apps/backend/src/farmable_backend/main.py:200-238` — routes `/auth/signup`, `/auth/verify/phone`,
  `/auth/verify/email`, `/auth/otp/resend`, `/auth/login`, `/auth/refresh`.
- `apps/backend/src/farmable_backend/account_api.py` — `/auth/logout`, `/auth/revoke-all`,
  `/account/profile` (GET/PATCH), `/account/farm` (GET/PATCH), `/account/export`, `DELETE /account`.
- `apps/backend/src/farmable_backend/integrations/turnstile.py` + `registry.py` + `settings.py` —
  Turnstile adapter exists, is registered, and is smoke-tested (`integrations/smoke.py:104-110`),
  but is **never called from any HTTP route**. `SignUpRequest`/`LoginRequest`
  (`apps/backend/src/farmable_backend/schemas.py:34-54`) are `StrictModel` (extra="forbid") and have
  **no `turnstile_token` field** — a client cannot even submit one today.
- `models.py` has `VoiceSessionRate`/`PhotoRate` (owner_id primary key, JSON `hits` list) as the
  established durable-rate-limit pattern in this repo, and `SyncMutation`
  (`mutation_id` unique + `request_fingerprint` hash) as the established idempotency-dedup pattern.
  Neither is applied to auth/account routes. No `rate_limit_counters` or idempotency-response table
  exists.
- `docs/account-api.md` "Limits still open" section explicitly defers per-account login-failure/
  refresh-abuse counters, `rate_limit_counters`, Turnstile on sign-up/login, and `Idempotency-Key`
  to "#7/#8 work". Per this task's explicit instruction, that deferral is **not accepted** for the
  backend adapter contract, fake-provider tests, fail-closed behavior, or abuse protection — only
  live provider delivery may stay with #7.
- `auth.py:147` / `:171-177` — signup raises `AuthError("account_exists", 409)` on an existing
  email/phone (both at the pre-check and via `IntegrityError` catch). Issue #9 requires the same
  response/status as a new signup.
- `auth.py:257-277 refresh()` — reusing an already-revoked/expired token raises `invalid_session`
  but does **not** revoke the user's other live sessions. Issue requires cascade-revoke-all on reuse.
- `account_schemas.py` `ProfileUpdate`/`FarmUpdate` — no `email`, `phone`, or farm location fields.
  Docstring: "Email and phone are deliberately not updatable here." Contradicts issue's "Transferred
  backend scope from #10": `PATCH /me` must support email, language, farm location and verified
  phone changes.
- `account_api.py:111-133 export_account` — synchronous, returns bytes directly. No job creation,
  status endpoint, rate limit, or expiring download link.
- No consent table/model anywhere in `models.py`.
- No retention-cleanup job/worker task found for sessions, verification challenges, rate-limit
  counters, idempotency records, or export artifacts.
- Named acceptance tests from the issue (`test_signup_verify_login`, `test_sms_rate_limit_per_phone`,
  `test_sms_daily_global_cap`, `test_refresh_reuse_revokes_all`,
  `test_signup_existing_email_same_response`, `test_login_sends_no_sms`,
  `test_unverified_user_blocked`, `test_turnstile_down_refuses`) — **none exist** anywhere in
  `apps/backend/tests` or `e2e/`. `e2e/api/test_auth.py` does not exist (only `test_smoke.py`,
  `e2e/degradation/test_dependencies.py` exist under `e2e/`).
- Password policy: `SignUpRequest.password` already enforces `min_length=15` (stricter than issue's
  10-char floor) — common-password-list check not yet verified.
- Migrations: 9 revisions exist, latest `0009_account_profiles.py`. Next revision is `0010`.
- Ownership boundaries (from issue text and #10's transferred-scope note): Flutter UI/device storage
  stays with #10; live SMS/Turnstile *provider credentials/delivery* may stay with #7, but the
  adapter contract, fake-provider tests, fail-closed behavior, idempotency and abuse protection stay
  with #9.

## Requirement matrix

Legend: Impl = implementation status on main; Gap = what's missing; PG = needs real-Postgres
concurrency test.

| # | Requirement | Impl on main | Gap | Prod path to change | Unit test | PG test | E2E | Failure test | Verify cmd |
|---|---|---|---|---|---|---|---|---|---|
| 1 | Turnstile before signup mutation, fail closed | adapter unused | wire into `/auth/signup`, `/auth/login`; add `turnstile_token` field; validate first | `main.py` routes, `schemas.py`, `auth.py` | new | - | `test_turnstile_down_refuses` | timeout/invalid/missing-config | `pytest apps/backend/tests/test_auth*.py -k turnstile` |
| 2 | Turnstile before login mutation | missing | same | same | new | - | new | same | same |
| 3 | Safe error contract on Turnstile failure, no token/secret logged | n/a | define error code + log masking | `main.py`, `logging.py` | new | - | - | - | grep logs in test |
| 4 | Durable signup/IP limit | missing | new table+row-lock counter, keyed hashed IP | new module `rate_limits.py`, `models.py` | new | PG concurrency | - | restart-survives | `pytest -k rate_limit_signup` |
| 5 | Durable SMS/phone (3/10min) | in-memory only (`auth.py:_send`) | move to persistent counter | `auth.py::_send` | new | PG | `test_sms_rate_limit_per_phone` | provider not called on reject | same |
| 6 | Durable SMS/IP | missing | new counter | same | new | PG | - | - | same |
| 7 | Daily SMS cap (50/day system-wide) | missing | new counter | same | new | PG | `test_sms_daily_global_cap` | - | same |
| 8 | Wrong-code attempt cap | exists in-memory (`MAX_OTP_ATTEMPTS`) via challenge row | verify persists across restart (it does, DB-backed) — likely OK, confirm | `auth.py::verify` | existing+new | PG | - | - | review only |
| 9 | Login failures/account | missing | new counter | `auth.py::login` | new | PG | - | - | same |
| 10 | Login failures/IP | missing | new counter | `main.py` route or middleware | new | PG | - | - | same |
| 11 | 429 + Retry-After + stable code on all above | partial (global limiter only) | apply to new counters | `rate_limits.py` | new | - | - | - | same |
| 12 | Idempotency-Key: signup | missing | new table, unique key+fingerprint+stored response | `auth.py::signup`, `main.py` | new | PG concurrency | - | same-key-diff-payload rejected | `pytest -k idempotency_signup` |
| 13 | Idempotency-Key: SMS send | missing | same pattern | `auth.py::_send`/resend route | new | PG | - | - | same |
| 14 | Enumeration-safe signup (no 409) | violates (409 today) | remove `account_exists` 409; unify success response; send warning SMS/email to real owner | `auth.py::signup` | rewrite `test_signup_existing_email_same_response` | PG (unique race) | yes | - | `pytest -k enumeration` |
| 15 | Login generic failure message | done | - | - | existing | - | - | - | - |
| 16 | Dummy password verify on missing account | done (`DUMMY_PASSWORD_HASH`) | - | - | existing | - | - | - | - |
| 17 | Refresh reuse revokes all sessions | missing | cascade-revoke on detected reuse | `auth.py::refresh` | new `test_refresh_reuse_revokes_all` | PG concurrency | yes | - | `pytest -k refresh_reuse` |
| 18 | Unverified users blocked from protected routes | needs audit | confirm 403 `phone_not_verified` contract everywhere | cross-cutting dependency | new `test_unverified_user_blocked` | - | yes | - | `pytest -k unverified` |
| 19 | Login never sends OTP | done | confirm test | - | new `test_login_sends_no_sms` | - | yes | - | - |
| 20 | Argon2id + password policy (10 char, common list) | length OK (15) | add common-password check | `schemas.py`/`auth.py` | new | - | - | - | - |
| 21 | No sensitive logging | needs audit | grep all log call sites in auth/account/rate-limit code | multiple | new | - | - | - | log-content test |
| 22 | Refresh tokens stored only as hash | done | - | - | - | - | - | - | - |
| 23 | Refresh rotation atomic | done (`UPDATE...RETURNING`) | - | - | - | - | - | - | - |
| 24 | Logout / revoke-all | done | - | - | existing | - | - | - | - |
| 25 | PATCH /me: email change + re-verify | missing | new flow: pending-change + OTP re-verify, uniqueness-safe | `account_api.py`, `account_schemas.py`, `account.py` | new | PG unique race | yes | - | new |
| 26 | PATCH /me: phone change + re-verify | missing | same | same | new | PG | yes | - | new |
| 27 | PATCH /me: farm location | missing | add lat/lon or geometry field to Farm update | `account_schemas.py`, `models.py` (Farm already may have location — verify), migration | new | - | yes | - | new |
| 28 | Export as durable job w/ polling + expiring link | sync-only today | new `export_jobs` table, worker/task, signed short-lived download token, rate limit | `account.py`, `account_api.py`, `tasks.py`/worker, migration | new | PG | yes | retry-safe | new |
| 29 | Export idempotent creation | missing | Idempotency-Key or dedupe on pending job | same | new | PG | - | - | new |
| 30 | Export cleanup after expiry | missing | retention job | worker task | new | PG | - | - | new |
| 31 | Deletion: password confirm, session revoke, credential removal | done | - | - | existing | - | - | - | - |
| 32 | Deletion: resumable/retry-safe partial failure | unclear (single txn today) | add deletion-progress tracking or ensure full idempotent retry | `account.py::delete_account` | new | PG (kill mid-delete) | - | interrupted-resume | new |
| 33 | Deletion: photos/uploads/export artifacts cleaned up | not verified — export/photo storage cleanup absent from `delete_account` | extend deletion to purge GCS/MinIO objects, export artifacts | `account.py`, `gcs_photos.py`/`uploads.py` | new | - | - | - | new |
| 34 | Consent model: stored + versioned + timestamped | missing | new `consents` table + endpoint | `models.py`, new `consent_api.py`, migration | new | - | yes | - | new |
| 35 | Consent enforced on operations (not just stored) | missing | gate relevant routes on consent state | cross-cutting | new | - | - | - | new |
| 36 | Retention cleanup: sessions/verification/rate-limit/idempotency/export | missing | scheduled worker tasks, bounded batches | `worker.py`/`tasks.py` | new | PG | - | - | new |
| 37 | Cross-account isolation audit (all authenticated routes) | needs full audit | enumerate every authenticated endpoint, confirm 404-on-cross-owner | cross-cutting | new + existing | PG | yes (contract) | - | new |
| 38 | OpenAPI/api-client regen | tooling exists (`make client`) | run after all route changes | - | - | - | - | - | `make client && make client-check` |
| 39 | `/security-review` before merge | required by issue | run this repo's `security-review` skill before opening PR | - | - | - | - | - | skill run |

## Named acceptance tests to add (all currently absent)
`e2e/api/test_auth.py::test_signup_verify_login`, `test_sms_rate_limit_per_phone`,
`test_sms_daily_global_cap`, `test_refresh_reuse_revokes_all`,
`test_signup_existing_email_same_response`, `test_login_sends_no_sms`,
`test_unverified_user_blocked`, `test_turnstile_down_refuses`.

## Open questions before implementation (flag, don't guess)
- Whether "farm location" needs geometry (PostGIS point, matching `Point` annotation already in
  models.py) or a simpler lat/lon pair — needs one-line confirmation, defaulting to reusing the
  existing `Point` annotated type used elsewhere in the schema for consistency.
- Whether export should keep `?format=json|zip` semantics as the job's final artifact shape, or
  change contract shape — defaulting to keep it, just move to async job wrapping the same document
  builder.
