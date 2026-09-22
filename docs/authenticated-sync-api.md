# Authenticated observation/photo API (#17 slice)

This backend slice does not close #17. It provides authenticated reads for
existing farms/sections, observation create/read, and durable photo processing.
#11 extends it with owner-scoped CRUD for sections, plantings, tasks, financial
records, saved plans and media metadata, observation edit/delete, and the ordered
change feed - see `docs/farm-records-api.md`. It still does not create farms,
provide cloud-photo download URLs, or connect the phone-local queue in PR 47.
Accounts with no farms see an empty list. Device acceptance remains separate.

## Request contract

Use the access token from `/auth/login` as `Authorization: Bearer ...`. Never use
the refresh token, send an owner ID, or serialize a local file path. The server
derives ownership from an active verified session and rechecks farm/section scope
on every request. Foreign and missing record IDs both return 404.

The generated `packages/api-client` contains the authoritative DTOs and bearer
security scheme. All lists use UUID keyset order, `limit` (default 50, max 100),
optional `cursor`, and `{items, next_cursor}`. This is not a change feed or a
snapshot across pages.

| Endpoint                                                   | Purpose                                                              |
| ---------------------------------------------------------- | -------------------------------------------------------------------- |
| `GET /farms`                                               | Active owned farms                                                   |
| `GET /farms/{farm_id}/sections`                            | Active sections                                                      |
| `GET /farms/{farm_id}/observations`                        | Active observations; optional `section_id`                           |
| `GET /farms/{farm_id}/observations/{observation_id}`       | One observation                                                      |
| `GET /farms/{farm_id}/changes` | Ordered change feed for #17 (see `docs/farm-records-api.md`) |
| `POST /farms/{farm_id}/observations`                       | Idempotent create; first and replay return 200                       |
| `POST /farms/{farm_id}/photo-uploads`                      | Reserve/replay one logical photo mutation                            |
| `POST /farms/{farm_id}/photo-uploads/{upload_id}/complete` | Accept durable processing intent (202), or return ready result (200) |
| `POST /farms/{farm_id}/photo-uploads/{upload_id}/retry`    | Explicit, attempt-fenced recovery after a temporary failure          |
| `GET /farms/{farm_id}/photo-uploads/{upload_id}`           | Processing status and final acknowledgement                          |

Observation create accepts `mutation_id`, `observation_id`, `section_id`, `type`,
`note`, required ISO timezone-aware `created_at`, and optional `health_status`,
`action_taken`, `created_by_voice`, and ready server `media_id`. Preserve the UUIDs
and logical payload through retries. Equivalent timestamps normalize to UTC.
Changing a mutation's payload or reusing an observation ID under another mutation
returns 409. The database mutation, observation, and change record commit together.
Requests are limited to 65,536 bytes and reject extra fields.

A new observation's `created_at` must be within 365 days before or five minutes
after database time, inclusively. Outside dates return 422
`observation_time_out_of_range`; they are never silently clamped. An exact accepted
mutation remains replayable after it ages outside that window. Changed payloads
still conflict, and current ownership/session checks still apply.

For a photo:

1. Keep the original file and pending observation on the phone. Reserve using a
   stable `mutation_id`, stable device-local `local_media_id`, `section_id`, MIME
   `content_type` (`image/jpeg` or `image/png`), and exact `byte_length` (1–5,000,000).
2. Persist the returned `upload_id`. While `awaiting_upload`, send the returned
   `form.fields` unchanged to `form.url` as multipart POST, then the file. Do not
   send the Farmable bearer token to GCS. The form is a five-minute credential;
   never log it. An exact reservation retry can refresh an expired form.
3. Call complete with no body (or `{}`). A 202 is not success: poll the status
   endpoint with bounded backoff. Duplicate completion cannot reset the budget.
4. Only `ready` includes `cloud_media_id`. Map the returned owner/farm/mutation/
   local entity IDs to the pending queue entry before accepting the acknowledgement.
   Use `cloud_media_id` as observation `media_id`, then create the observation.
5. Keep local files/records when any request fails. This API never instructs local
   deletion. A failed attempt never resets through ordinary reservation, completion
   or polling. Corrected invalid content needs new local media and mutation IDs;
   temporary failures support explicit recovery below. An expired, never-processed reservation can be reopened by an
   exact replay, retaining its logical identity but receiving a different attempt key.

Every upload response includes `attempt_id` and `retryable`. After a `failed`
response with `retryable: true`, an explicit retry action sends
`{"failed_attempt_id": "<that attempt_id>"}` to the retry endpoint. It returns
200 with a new attempt and `awaiting_upload`, preserving the original upload,
mutation, local media and future cloud media IDs. It does not return a signed
form: replay the original reservation to get a fresh form, upload the retained
local file again, then complete/poll normally.

If the retry response is lost, repeat the same `failed_attempt_id`. It returns
current status without creating another attempt—even if the successor has since
failed. A further explicit recovery must name that later failed attempt. Never
loop automatic recovery to replenish exhausted budgets. Each fresh attempt has
four processing claims and all recovery requests consume the shared write quota.
Invalid photos, active attempts and ready media cannot be reset. Unknown/foreign
attempt IDs return 404; ineligible current state returns 409. Old worker/cleanup
claims cannot touch the replacement attempt's keys.

The queue's local `createdAt` milliseconds must become an ISO timestamp, and its
camelCase properties must map to the generated HTTP DTOs. Do not enable the real
transport until those mappings, auth pauses, upload-ID persistence, polling, and
acknowledgement checks are implemented and tested on Android/iOS.

## Failure handling and concurrency

401 means pause for valid credentials; 404 means the scoped target is unavailable;
409 means conflict and must not trigger a changed-payload automatic replay;
413/422 require corrected input. Respect `Retry-After` on 429/503. Retry transport
failures with the same logical IDs. A lost response does not prove a failed write.

Upload `error_code` is restricted to `temporarily_unavailable`, `invalid_photo`,
`target_unavailable`, or `upload_failed`; provider/IAM details are not returned.
Use the explicit `retryable` flag, not a guessed provider cause, to offer recovery.
Internal fixed codes remain in the database for authorized diagnostics.

Photo write admission is 30 requests per authenticated owner per rolling minute,
shared through PostgreSQL; status reads do not consume that quota. Existing
peer-IP protection remains. Each API process admits eight synchronous record
operations and two photo reservations in separate pools. Slow credential discovery,
bucket checks or signing cannot occupy the record pool. Both pools hold admission
until cancelled work actually finishes. Credential discovery has one in-flight
initializer; other reservations receive a retryable 503 immediately. Failed
initialization is retried only after a 30-second cooldown. Disabled storage is
cached until restart and returns `photo_storage_disabled`; ordinary records remain
available.

Two photo slots in the existing worker process discover committed intents at
startup and repeatedly. No client resend or successful broker notification is
needed after a worker restart. Claims use 120-second leases, renewed every 30
seconds. Stale claims cannot finalize. Transient errors have three retries after
the first attempt (5, 30, 120 seconds); crashed claims consume the same persisted
budget. Failed status records remain visible to their owner.
Signer configuration, credential-kind and bucket-privacy configuration failures
are recoverable deployment failures. Privacy checks still reject all unsafe
operations; after correcting the deployment, explicit retry preserves the same
logical photo identity even if its processing budget was exhausted.

The worker pins the incoming object generation, decodes and sanitizes actual
pixels, then creates a separate private clean object. Replayed forms cannot write
that key. A crash between object creation and database commit is reconciled by
verifying existing clean bytes; only a successful database finalization makes
the photo attachable. Existing legacy media is not assumed validated.

The janitor only visits recorded attempt keys and exact object generations.
Abandoned attempts expire after an hour; cleanup waits another hour after expiry
or completion and until issued forms are expired. It preserves referenced ready
clean objects and database idempotency history. Each storage cleanup handles at
most 100 generations before yielding for a later pass. Bucket-wide versioning
and retention policies are not changed.
Shutdown stops admission of further cleanup attempts and generation deletions.
The current SDK call may still finish within its transport/retry budget; this is
cooperative cancellation, not a guaranteed container-grace-period deadline.
An interrupted cleanup remains unfinished and can resume on a later worker pass.

## Configuration and rollout prerequisites

The feature is disabled for cloud uploads unless `PHOTO_BUCKET` is configured.
Also set `PHOTO_SIGNER_EMAIL` to the approved Google service account identity.
Photo-free observation operations do not require storage configuration.

Use workload/application-default credentials, not downloaded service-account
keys or HMAC secrets. The factory rejects service-account private-key credentials.
The runtime and signing identities must have the permissions needed for their
actual operations, scoped to the designated bucket/service account:

- Runtime: `storage.buckets.get` to verify privacy; `storage.objects.get`,
  `storage.objects.create`, `storage.objects.list`, and `storage.objects.delete`
  for validation, private publication, and generation-scoped cleanup.
- Signing identity: permission to create the signed incoming objects in that
  bucket. The runtime must have `iam.serviceAccounts.signBlob` on this identity.
- Enable the IAM Service Account Credentials API. Do not assume the existing
  `roles/storage.objectAdmin` bucket grant also supplies bucket inspection or
  IAM signing permissions. Have the infrastructure owner review the grants.

The bucket must report uniform bucket-level access and enforced public-access
prevention. Missing configuration, unverifiable privacy, unavailable signing,
or unavailable credentials fails closed. Forms/URLs, tokens, image bytes, notes,
and raw provider exceptions must not appear in logs. [Google's IAM signing
guide](https://docs.cloud.google.com/storage/docs/access-control/signing-urls-with-helpers)
and [policy constraints](https://docs.cloud.google.com/storage/docs/authentication/signatures)
describe the required signing capability and upload restrictions.

Revision `0005` adds only photo bookkeeping/rate tables and indexes. Apply it
explicitly during an authorized rollout, before enabling the feature; never on
API startup. Existing users/farms/records/media are neither rewritten nor
backfilled. Operational rollback disables the feature/reverts application code
and retains new tables/data. A schema downgrade deletes those new records and
is not the normal rollback procedure.

The offline migration linter cannot see PostgreSQL connection startup settings
and flags missing `SET lock_timeout`/`SET statement_timeout` in its generated SQL.
The migration connection actually uses 1-second lock and 5-second statement
timeouts, with a real contention/rollback regression test. Keep the warning
visible for the existing maintainer `migration-approved` review gate; do not
disable the rules or inject a fake approval environment variable to make it pass.

No rollout, cloud permission change, live migration, or live cleanup is performed
as part of implementation. Confirm API and worker receive the same approved
bucket and signing configuration before enabling uploads.

The deployment must keep a worker running with CPU available for background
processing; an API-only or request-throttled worker deployment cannot guarantee
timely recovery. Size worker memory for two simultaneous decodes of up to
20-million-pixel images plus the existing jobs. These limits bound admission,
not measured memory consumption or throughput; verify both under staging load.

## Verification and opt-in staging acceptance

Local checks cover the generated contract, ORM parity, authorization, exact
replays, strict input, rate limiting, worker failures, and injected SDK behavior.
The PostgreSQL integration suite uses random schemas in a disposable CI database:

```sh
uv run pytest apps/backend/tests/test_records_api.py apps/backend/tests/test_gcs_photos.py apps/backend/tests/test_photo_migration.py
# Use the repository's disposable database harness, ENVIRONMENT=ci:
uv run pytest apps/backend/tests/integration/test_photo_sync_postgres.py -m integration
make lint typecheck check-no-raw-sql migration-safety
make client-check security-audit
```

`make test` deliberately excludes integration tests; SQLite does not prove row
locking. The existing required GitHub check `integration-tests` runs
`make test-integration`, which now explicitly executes the entire
`test_photo_sync_postgres.py` file against PostgreSQL before stopping dependencies.
This includes simultaneous same-photo recovery, one publication, stale worker and
old cleanup fencing, and migration contention. `scripts/tests/test_photo_sync_ci.py`
guards suite selection. No branch-protection changes or new CI privileges are needed.

After separate authorization, use an isolated staging bucket and synthetic
verified accounts/farms. Record deployed commit, migration revision, API/worker
configuration identities (not tokens), and these outcomes:

1. Reserve and upload a synthetic JPEG containing test EXIF/GPS; verify the form
   rejects wrong key, type, length, and expired credentials against real GCS.
2. Complete/poll to ready; inspect the exact cleaned object generation using the
   authorized operator identity and verify EXIF/GPS removal and anonymous denial.
3. Repeat reservation/completion and observation creation concurrently and after
   losing HTTP responses. Confirm exactly one owned media row, observation, and
   change per mutation, with no cross-account access.
4. Interrupt/restart the worker in the isolated environment during processing;
   verify intent recovery, preserved pinned input, bounded retries, and no duplicate
   publication. Use a corrupt file to prove failed validation publishes no media.
5. Exercise cleanup only on those synthetic recorded attempts; verify ready clean
   objects and unrelated objects survive. Follow the approved staging retention
   procedure when removing fixtures—never use a bucket-wide deletion.

Injected SDK tests and emulators do not prove live GCS signing/IAM enforcement.
Real device airplane-mode/restart/reconnect acceptance is still required for #17.
