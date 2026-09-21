# PR49 review fixes

Status: approach approved; written specification awaiting confirmation.
Baseline: `72220646d4e0281a5c7fbe980a8ecd5311b9b59d`.
Review: https://github.com/ctrl-alt-elite-za/Farmable/pull/49#issuecomment-5765425776

## Scope and decisions

Address the review on PR49's existing branch. No merge, deployment, live database
or storage changes, branch-protection edits, mobile changes, or new entity APIs.
This amendment supersedes the original design's blanket terminal-photo rule.

Automatic reopening on reservation was considered but rejected: ordinary retries
and polling must not replenish processing budgets. Explicit recovery preserves
the photo identity without creating a second cloud media record.

## Explicit photo recovery

Add `POST /farms/{farm_id}/photo-uploads/{upload_id}/retry`, accepting only
`failed_attempt_id` (UUID). Upload responses include the current `attempt_id` and
a boolean `retryable`; IDs remain opaque and do not grant access.

- Authenticate and apply the existing owner-wide photo-write quota. Lock active
  farm, section, upload, then attempt, using the existing ordering.
- Recover only a failed current attempt whose internal failure is one of
  `incoming_missing`, `storage_unavailable`, `private_bucket_unverified`, or
  `retry_exhausted` (including exhausted crashed claims).
- Retain the original mutation fingerprint, local photo ID, upload ID and future
  cloud media ID. Create one fresh attempt/key with the existing four-claim budget;
  clear the upload's failure and return `awaiting_upload` with HTTP 200.
- Return no signed form from retry. The client replays its original reservation
  to obtain a form, re-uploads its retained local file, and completes normally.
- Duplicate requests naming the same old attempt return current status without
  creating another attempt or resetting its budget, even if a later attempt has
  since failed. A fresh recovery requires that later failed attempt's ID.
- Unknown/foreign attempts cannot mutate this upload. Ready, processing, queued,
  or permanently invalid current attempts cannot be reset. Corrupt/type/size
  failures remain terminal; corrected content is a distinct photo mutation.
- Old attempts and cleanup records remain intact. Old forms, cleanup claims and
  workers cannot affect a successor attempt's objects or publish a second media.

No new schema is needed: existing attempt IDs/sequences provide recovery fencing.

## Timestamp and response boundaries

For a previously unseen observation mutation, use database time to require
`now - 365 days <= created_at <= now + 5 minutes`; reject outside with 422 rather
than silently changing the farmer's timestamp. Exact previously accepted replays
remain valid as time passes, with existing fingerprint and ownership checks.

Expose a fixed public photo error vocabulary (`temporarily_unavailable`,
`invalid_photo`, `target_unavailable`, `upload_failed`) instead of raw adapter
codes. Unknown codes map to `upload_failed`. The explicit `retryable` flag tells
clients whether recovery is supported. Internal codes remain in the database and
may be logged only through an allowlist, never provider exception text or URLs.

## CI and smaller corrections

The existing `integration-tests` check is already required on main. Its harness
currently excludes the photo suite through a `-k` filter. Add an explicit invocation
of `test_photo_sync_postgres.py` while the isolated database is running, and a
regression protecting that selection. Reuse the job; do not alter branch rules.
Document the command and required check in the API documentation.

Use the same view dispatch for list/single-record reads. Construct the photo
database/worker only when configured, with safe partial-startup/shutdown cleanup.
Use `min(hits)` for quota expiry. Centralize retry delays and derive
`MAX_CLAIMS = len(RETRY_DELAYS) + 1` for runtime and ORM constraints. Historical
migration 0005 stays frozen; parity tests must catch any future budget/schema drift.
Redact exact root and descendant Google, urllib3 and requests logger messages.

## Verification

Test transient exhaustion followed by same-photo recovery and one publication;
duplicate/concurrent recovery; lost responses; late old retries after another
failure; permanent failures; scope/descriptor rejection; stale workers and old-key
cleanup. Run concurrency cases on disposable PostgreSQL, not SQLite.

Test both timestamp boundaries, absurd dates, UTC equivalence and aged exact
replays; public error mapping; optional worker startup/shutdown; unordered quota
hits; claim-budget/schema parity; logger roots and children; CI test selection.
Regenerate the API client and run lint, type checks, unit/integration tests,
generated-client drift and unchanged migration safety checks. Keep maintainer
migration approval and real GCS staging acceptance outstanding.

## Design checklist

- [x] Inspect review, affected code, CI logs and required-check configuration.
- [x] Compare recovery approaches; confirm scope and timestamp policy with user.
- [x] Write specification and self-review for scope, replay and cleanup ambiguity.
- [ ] User confirms this written specification.
- [ ] Write implementation plan, implement regressions/fixes, verify and push PR49.

No visual design is involved. The writing-plans skill is unavailable in this
session; after written-spec confirmation, use a checked-in implementation plan.
