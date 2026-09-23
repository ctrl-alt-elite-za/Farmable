# Account, privacy and session API (#9 backend slice)

This backend slice closes the server side of #9: protected account/profile reads
and writes, farm details, session revocation, account export and account
deletion. It does not add Flutter screens, secure device storage, permissions or
offline UI - those belong to #10 - and it does not enable live SMS or email
providers, which stay with #7. The deterministic fake OTP provider is unchanged
and the production provider still fails closed.

## Request contract

Use the access token from `/auth/login` (or from `/auth/verify/email`) as
`Authorization: Bearer ...`. Never send the refresh token and never send an owner
ID: the server derives ownership from an active, phone- and email-verified
session and rescopes every query to it. Unverified sessions, revoked sessions,
expired sessions, malformed tokens and deleted accounts all return
`401 invalid_session` with `WWW-Authenticate: Bearer`. Request models reject
unknown fields with `422 validation_error`.

| Endpoint                 | Purpose                                                   |
| ------------------------ | --------------------------------------------------------- |
| `POST /auth/logout`      | Revoke the calling session only (204)                     |
| `POST /auth/revoke-all`  | Revoke every session the caller owns (204)                |
| `GET /account/profile`   | First name, surname, phone, email, verification, language |
| `PATCH /account/profile` | Update first name, surname and/or preferred language      |
| `GET /account/farm`      | The caller's farm: id, owner, name, preferred language    |
| `PATCH /account/farm`    | Update the farm name and/or preferred language            |
| `GET /account/export`    | `?format=json` or `?format=zip`                           |
| `DELETE /account`        | Password-confirmed account deletion (204)                 |

Every account owns exactly one farm, created empty and named `My farm` at
sign-up. `GET /account/farm` returns the caller's oldest active farm and `404
not_found` when none remains.

Preferred language lives on the account, in `account_profiles`, and is echoed in
both the profile and the farm representation. The accepted values are `en`, `af`,
`nso`, `st`, `xh` and `zu`; anything else is `422 validation_error`. Email and
phone are deliberately not editable here, because changing either needs a fresh
OTP round through the existing `/auth/verify/...` routes.

## Export

`GET /account/export?format=json` returns `application/json` with
`Content-Disposition: attachment; filename="farmable-export.json"`.
`?format=zip` returns `application/zip` with
`filename="farmable-export.zip"` holding a single entry named `export.json`.
Both names are constants, so no caller input reaches the header or the archive
and no traversal is possible. Both responses are `Cache-Control: no-store`.

The document is deterministic: keys are sorted, rows are ordered by primary key,
the archive uses a fixed entry timestamp, and no generation timestamp is
included, so two consecutive exports are byte-identical. It contains
`schema_version`, `account` (identity and language, never credentials), and the
caller's `farms`, `sections`, `plantings`, `media`, `observations`, `tasks`,
`financial_records`, `saved_plans` and `sync_mutations`.

It never contains password hashes, OTP hashes or challenge rows, access- or
refresh-token hashes, internal secrets, or any other account's data.

## Deletion

`DELETE /account` requires `{\"password\": \"...\"}`. A missing password is `422`, a
wrong password is `401 invalid_credentials`, and neither changes any data. On
success the server soft-deletes the caller's farms and owned records, then
deletes the `account_profiles`, `auth_sessions`, `verification_challenges` and
`auth_identities` rows for that account.

The `users` ownership row is kept on purpose. A hard delete of `users` would
cascade through `farms` into `sync_mutations` while `photo_uploads` and
`photo_rates` still reference them without an `ON DELETE` action, so the delete
would either fail or destroy referenced history. Keeping the ownership row
preserves referential integrity while removing every credential, so a deleted
account cannot log in, cannot refresh a previously issued token, and cannot
reach any authenticated endpoint. Other owners are unaffected.

## Schema

Revision `0007` adds one new, empty table, `account_profiles`, keyed by the
identity UUID with `ON DELETE CASCADE` and a check constraint on the language
vocabulary. No existing table is altered and no data is backfilled, so legacy
`users` rows and existing farm ownership are preserved. The downgrade drops the
table, which deliberately discards stored language preferences and falls the
application back to the `en` default; identities, sessions and farms survive it.

## Limits still open

Per-account login-failure and refresh-abuse counters, the durable
`rate_limit_counters` table, Turnstile on sign-up and login, `Idempotency-Key`
handling and the live Twilio adapter remain #7/#8 work. Only the existing global
per-IP limiter, the OTP send window and the OTP attempt cap apply here.

## Checks run for this change

- `uv run pytest` - full suite (`scripts/tests` and `apps/backend`)
- `uv run ruff format .`, `uv run ruff check .`, `uv run mypy`
- `bash scripts/check-no-raw-sql.sh`
- `uv run python scripts/migration_safety.py`
- `uv run python scripts/generate_client.py` with no remaining contract diff
- `pnpm -r --if-present run typecheck`
- `apps/backend/tests/integration/test_account_postgres.py` is collected here but
  needs the disposable Compose stack (`make test-integration`) to execute.
