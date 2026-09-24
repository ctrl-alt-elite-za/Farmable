# Gemini Live credential handoff

This is a partial implementation of #7 on the merged adapter/authentication
foundation. **Do not close #7:** real-provider acceptance and SMS/email delivery
remain outstanding. This change does not implement Flutter audio, #24, deployment
#6, or a voice-controlled planner.

## Endpoint

For the farm assistant, use the new [conversation-scoped contract](assistant-live.md).
The endpoint below remains a compatibility handoff without farm tools or
conversation-specific consent. Gemini Live remains the selected voice provider.

`POST /voice/live-session`, with `Authorization: Bearer <Farmable access token>`.
Send **no body and no query parameters**. Both phone and email must be verified;
expired, revoked, duplicate, or invalid credentials receive `401`. The caller
cannot select a user, model, token lifetime, tools, or unrestricted use count.

The generated API client contains `createLiveSession`. A successful response has:

| Field                    | Meaning                                                             |
| ------------------------ | ------------------------------------------------------------------- |
| `credential`             | Secret ephemeral token. Keep only in memory; never log or persist.  |
| `new_session_expires_at` | Connect before this UTC timestamp (60 seconds from issuance start). |
| `expires_at`             | Token expiry (10 minutes from issuance start).                      |
| `model`                  | Server-selected `models/<GEMINI_LIVE_MODEL>`.                       |
| `api_version`            | `v1beta`.                                                           |
| `mode`                   | `live` or `fake`; a fake credential cannot connect to Google.       |

Successful responses use `Cache-Control: no-store` and `Pragma: no-cache`.
Only the ephemeral token is returned, never `GEMINI_API_KEY` or arbitrary provider
response fields. Provider errors have fixed codes and no upstream body/exception.

| HTTP/code                                             | Client behavior                                        |
| ----------------------------------------------------- | ------------------------------------------------------ |
| `401 invalid_session`                                 | Reauthenticate; do not retry the same token.           |
| `422 validation_error`                                | Remove the request body/query parameters.              |
| `429 voice_rate_limited`                              | Honor `Retry-After`; keep non-voice controls usable.   |
| `503 voice_disabled`                                  | Voice is not configured; use non-voice controls.       |
| `503 voice_timeout` / `voice_unavailable`             | Show temporary unavailability; no automatic mint loop. |
| `503 capacity_unavailable` / `dependency_unavailable` | Honor `Retry-After`; allow manual retry.               |

The existing global IP rate limiter and database-error handling also apply.
Losing the response can consume one issuance: tokens are deliberately neither
cached nor replayed, and provider POST requests are **never automatically retried**.

## Configuration and limits

Apply additive migration `0006` explicitly before enabling the endpoint; startup
does not migrate the database. Roll back by disabling credential issuance first,
then downgrading to `0005`; that removes quota history, not farm or auth records.

For isolated local/CI contract tests set `ENVIRONMENT=ci`,
`INTEGRATIONS_MODE=fake`, `GEMINI_LIVE_ENABLED=true`, and
`GEMINI_LIVE_MODEL=fixture-live-model`. No key or network is needed. Fake mode is
allowed only in CI/staging and never silently falls back to a live provider.

For an owner-approved staging run use `ENVIRONMENT=staging`,
`INTEGRATIONS_MODE=live`, `GEMINI_LIVE_ENABLED=true`, an explicitly selected
available `GEMINI_LIVE_MODEL`, and `GEMINI_API_KEY`. The Live model is deliberately
separate from `GEMINI_MODEL` used by ordinary generation. Store the key in the
proposed Secret Manager secret `farmable-staging-gemini-api-key` and inject it into
the backend only, as part of #6. This PR neither creates secret versions nor
activates billing/deployment. Do not bundle the server key in Flutter.

- At most 3 issuance attempts per rolling minute and 20 per rolling hour per
  authenticated owner, shared across sessions, replicas, and restarts via the DB.
  Failed/abandoned provider calls consume admission. Disabled calls do not.
- At most 4 in-flight mint requests per API process; each has a 10-second budget.
- Existing Gemini fault flag applies. The Live adapter has its own circuit:
  5 failed calls open it for 30 seconds, then one probe is admitted.
- Tokens permit one new session and a fixed AUDIO setup with session resumption.
  The complete setup is locked; arbitrary client tools/overrides are not supported
  in this slice. Farm context, tool calls, and planner execution require a separate
  reviewed contract, not caller-provided token policies.
- These are admission limits, **not a billing cap**. Live usage can incur charges;
  configure account/project quotas and budgets before enabling it. Many accounts
  can still consume project quota. There is no backend audio proxy or offline voice.

## Provider contract and remaining verification

The operator's `make smoke-voice` tool now exercises authenticated issuance and
one bounded text-input/audio-output Live turn without a Flutter client. Follow
[provider verification](provider-verification.md). This does not replace the
device, microphone, token-reuse, expiry or resumption acceptance checks below.

The adapter uses Google's
[v1beta REST discovery schema](https://generativelanguage.googleapis.com/$discovery/rest?version=v1beta),
checked 2026-09-22: `POST /v1beta/auth_tokens`, `uses`, expiry timestamps, and
`bidiGenerateContentSetup`. An omitted `fieldMask` locks the complete setup.
Only the output `name` is required; expiry fields are input-only, so the response
reports the server's requested policy timestamps, not invented provider echoes.

The [ephemeral-token guide](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens)
uses the SDK-style `liveConnectConstraints` wrapper even in its constrained REST
example. We follow the machine-readable REST schema, not that wrapper. Synthetic
contract tests cannot prove live acceptance; verify this exact wire request on
the selected account/model before enabling the client feature.

Remaining acceptance, requiring the owner-provisioned #6 environment and explicit
approval for provider usage:

1. Use a verified staging Farmable session to request one credential without
   printing its value, server key, or auth headers in terminal/CI logs.
2. Have the #24 client connect with that ephemeral credential and returned model
   using v1beta. Test AUDIO setup, one new session only, the connection deadline,
   expiry, and resumption within the expiry window. Never record the token.
3. Record only sanitized status, model, UTC times, and pass/fail evidence. Confirm
   model availability, quota/budget settings, and the response shape; synthetic
   fixtures are not recorded live-provider evidence.
4. Test denial/timeouts with non-voice UI controls still usable. Run real SMS/email
   smoke separately; this endpoint does not wire the existing adapters into OTP.

Automated coverage: authenticated fake HTTP flow, rejected sessions and policies,
durable rate history, fixed REST policy, malformed responses, circuit/fault/timeout,
cancellation/concurrency, secret omission, OpenAPI, and additive migration shape.
SQLite unit tests do not prove PostgreSQL row-lock concurrency; the dedicated
integration tests require the disposable PostgreSQL harness.
