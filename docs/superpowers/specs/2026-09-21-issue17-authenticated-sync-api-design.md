# Issue 17: authenticated observation and photo synchronization API

Date: 2026-09-21

Status: written specification approved by the user on 2026-09-21.

The approved [PR49 review amendment](2026-09-21-pr49-review-fixes-design.md)
adds explicit recovery of temporarily failed photo attempts, bounds new observation
timestamps, and narrows public failure codes. It supersedes conflicting original
terminal-failure wording below; ordinary reservation/completion replays still cannot
reset a failed attempt.

Baseline: `origin/main` at `e32a53e` (backend authentication from PR 44).
Implementation branch: `issue-17-authenticated-sync-api`.

## Objective and scope

Expose a narrow production-oriented API over the existing ownership schema and
observation repository: authenticated farm/section reads, observation create/read,
and durable, retry-safe photo upload completion using Google Cloud Storage (GCS).
This is a backend slice of issue 17, not completion of the issue or a working
end-to-end mobile synchronization feature.

The user approved GCS and the direct-upload/worker-validation approach. No merge,
deployment, cloud provisioning, live database migration, or live data cleanup is
authorized. Test data must be disposable and isolated from developer/live data.

Excluded: farm/section creation or editing; observation editing/deletion; tasks,
finance, plans, audio uploads, mobile screens/authentication/transport integration,
and a general bidirectional change-feed protocol. Existing accounts without farms
receive an empty farm list; this API does not silently provision sample records.
PR 47 remains a separate phone-local queue change. Issue 17 remains open until its
full acceptance criteria, including native restart/reconnect behavior, are proven.

## Decisions and structural constraints

1. Reuse FastAPI, the SQLAlchemy ORM, `FarmRecordRepository`, `SyncMutation`, the
   existing session model, and the current worker. Do not implement a parallel
   account system, raw SQL layer, or demo-storage-backed production API.
2. Use short-lived signed POST policies to upload directly to private GCS, then
   validate in the worker. An API upload proxy would consume API bandwidth and
   image-processing capacity; a resumable upload protocol is unnecessary for the
   existing 5,000,000-byte photo limit.
3. Keep the existing S3 adapter and its tests intact. Reuse its provider-independent
   photo sanitizer, but introduce a GCS adapter instead of treating S3 signing or
   encryption headers as GCS-compatible. Current infrastructure defines a GCS
   bucket, while `uploads.py` currently implements S3.
4. Keep routes/DTOs, authorization, transactional record services, and cloud I/O in
   separate modules. Synchronous SDK calls and decoding must not block the API's
   event loop or consume the password-hashing executor.
5. Use additive upload bookkeeping. A media row alone does not currently record
   upload validation, immutable source generation, or processing ownership.
   Existing media rows must not be backfilled as validated by assumption.
6. The future mobile transport translates the local queue's camelCase values and
   millisecond timestamps to the HTTP DTOs. Local file paths and client owner IDs
   never become trusted HTTP inputs. That transport is not implemented here.

## Authentication and ownership

Protected routes accept only an `Authorization: Bearer` access token. Hash it and
look up the existing `AuthSession`; require an unexpired, unrevoked session and a
phone/email-verified identity. Refresh tokens are not access tokens. Token parsing
is bounded; missing, malformed, expired, revoked, and unknown tokens return the
same sanitized 401 error, with the appropriate bearer challenge.

Derive `owner_id` from the authenticated identity. Every farm, section,
observation, upload, and media lookup must constrain owner and farm and exclude
tombstoned parents/records. Return 404 for inaccessible IDs without disclosing
another owner's records. Reject submitted ownership, storage keys, object URLs,
and unknown request fields. Validate scope before looking up a replay so a saved
mutation cannot bypass current authorization.

For writes, verify and lock the active owned farm/section inside the transaction
that commits the mutation, consistently locking farm before section. Worker
completion rechecks and locks those relationships before
publishing media. A deleted parent must not gain a new active child through a
late request or worker result.

## HTTP contract

Routes are relative to the existing API root; do not introduce a new prefix for
this slice. Each operation has explicit OpenAPI DTOs and stable operation IDs.

| Method and path                                            | Contract                                                                            |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------- |
| `GET /farms`                                               | List active owned farms.                                                            |
| `GET /farms/{farm_id}/sections`                            | List active sections of an active owned farm.                                       |
| `GET /farms/{farm_id}/observations`                        | List active observations, optionally filtered by an owned `section_id`.             |
| `GET /farms/{farm_id}/observations/{observation_id}`       | Read one active owned observation.                                                  |
| `POST /farms/{farm_id}/observations`                       | Create/replay one observation mutation.                                             |
| `POST /farms/{farm_id}/photo-uploads`                      | Reserve/replay an upload and obtain a signed form when upload is needed.            |
| `POST /farms/{farm_id}/photo-uploads/{upload_id}/complete` | Durably request validation; return 202 while pending or 200 when ready.             |
| `GET /farms/{farm_id}/photo-uploads/{upload_id}`           | Read scoped processing state and, only when ready, the cloud media acknowledgement. |

List responses use `{items, next_cursor}` with default limit 50, maximum 100,
deterministic UUID keyset ordering, and strictly validated cursors. A cursor only
selects a position; it never grants access. Lists are current-state reads, not
snapshot-consistent exports or substitutes for a synchronization change feed.

Observation input: `mutation_id`, `observation_id`, `section_id`, `type`, `note`,
optional `health_status`, `action_taken`, `media_id`, `created_by_voice` (default
false), and required timezone-aware `created_at`. UUIDs and timestamps are parsed
strictly. Match existing local/schema bounds: nonblank type at most 100 characters,
nonblank note at most 10,000, optional health at most 100, optional action at most
10,000. Preserve client creation time; the change stream supplies server ordering.
Bound JSON request bodies to 65,536 bytes, including requests without Content-Length.

The wire `media_id` maps to the ORM's historical `local_media_id` foreign key; it
must identify a ready upload in this owner/farm/section, not a device-local UUID or
an unvalidated legacy media row. Photo-free observations remain supported.

Return 200 for both first observation creation and exact replay, with
`mutation_id`, `entity_id`, `owner_id`, `farm_id`, `version`, and the observation.
Reuse the repository's canonical fingerprint and transaction/savepoint logic;
normalize equivalent timestamps before fingerprinting. A same-ID/different-input
request returns 409. Different mutation IDs cannot create the same observation
ID twice. Insert the observation, mutation, and change record atomically. Do not
claim exactly-once HTTP delivery; the guarantee is one committed record per
accepted logical mutation despite at-least-once requests.

Upload reservation input: `mutation_id`, device-local `local_media_id` UUID,
`section_id`, `content_type` (JPEG or PNG), and `byte_length` (1–5,000,000). Persist
its immutable canonical fingerprint and generate server upload/media identities.
Use the existing globally unique mutation namespace for both entity types, so
an observation mutation ID cannot be reused for a media mutation. Same local media
identity with a different mutation or descriptor is a conflict, not an implicit
overwrite. Exact reservation retries return the same upload identity and state;
short-lived credentials may be refreshed while awaiting bytes.

Reservation/status responses echo the authorized owner/farm, original mutation
ID and local entity ID, and an opaque `upload_id`. Only the `ready` response includes
`cloud_media_id`. A signed form is `{url, fields, expires_at}`; clients must send
all supplied fields and then the file using multipart POST. No permanent public
URL, local path, or worker/provider exception is returned.

The complete operation takes no storage descriptor from the caller. Repeated
completion uses the same upload as its idempotency key; it cannot change content
type, size, owner, section, storage destination, or reset processing attempts.

## Durable upload state and processing

Add ORM-managed upload and upload-attempt bookkeeping with owner/farm/section
foreign keys, a unique mutation link, immutable descriptor, current attempt ID,
state, timestamps, retry count, next attempt time, processing lease token/expiry,
pinned source generation, and cleaned object descriptor/checksum. State values:
`awaiting_upload`, `queued`, `processing`, `ready`, `failed`, `expired`.

The upload row is also the durable work intent. Completion atomically transitions
an awaiting upload to queued before returning 202. A periodic task on the existing
worker scans at startup and every five seconds, at most 100 due intents per scan;
queue notifications may accelerate
work but cannot be the only way it is discovered. Worker startup and recurring
scans recover committed intents after crashes or enqueue failures. No second
application-managed task broker is introduced.

Claim due work with short ORM transactions and a 120-second renewable lease,
renewed every 30 seconds using database time and a fresh fencing token per claim.
Claim only work for which processing capacity is available. Release the database transaction before cloud
I/O or decoding. Conditional finalization must still own that lease token. A
superseded worker cannot publish a ready row or replace the accepted object.
Limit photo processing to two active jobs per worker process; do not prefetch an
unbounded collection of photo bytes or create an unbounded executor backlog.

On the first successful metadata read, pin the incoming object's GCS generation
and descriptor to the claimed attempt. Read only that generation with bounded
raw byte reads. Validate exact declared length/type, reject unexpected content
encoding, then call the existing sanitizer: real JPEG/PNG decoding, no animation,
at most 20 million pixels, orientation applied, metadata removed, and output at
most 5,000,000 bytes. MIME headers alone never establish validity.

Write clean data privately to an attempt-specific server-controlled key using a
create-only generation precondition. Persist enough trusted checksum/generation
information to reconcile a successful storage write followed by a database
failure. If the key already exists on retry, verify its descriptor and checksum;
do not overwrite it or accept unrelated bytes. Finalization atomically creates
one ready `Media` row, records its clean object key/generation, emits one media
change record, and marks the upload ready. Processing can run more than once;
publication has one logical result. A repeated completion after readiness returns
that result and never reads a later replacement of the incoming object.

Use one initial processing attempt and at most three automatic retries for
transient failures, delayed 5, 30, and 120 seconds. Persist attempts before work,
including crashed claims. Exhaustion and invalid images produce a durable failed
state with a fixed code; polling/repeated completion never replenishes the budget.
Missing incoming data is retryable within that budget. Corrected photo content
after a terminal failure requires new local media/mutation IDs. Do not silently
reuse the old mutation for changed bytes.

An awaiting attempt expires after one hour without accepted completion. An exact
reservation replay may reopen an expired, never-processed upload with a fresh
attempt/key while retaining its logical upload/media identity. Old forms cannot
target the replacement key. Already queued, failed, or ready uploads do not reset
through reservation replay. Refreshing a form extends the awaiting deadline.

## GCS boundary, configuration, and cleanup

Policies expire after five minutes and bind the configured bucket, one exact
incoming key, exact declared byte length and MIME type. No client-selected key
prefix, destination bucket, ACL, redirects, or arbitrary upload metadata. Forms
grant no writes to clean keys. Treat every form field/URL as a bearer credential:
redact logs, reprs, traces, and errors; return `Cache-Control: no-store`.

Use application-default/workload credentials and IAM-backed signing; no service
account key files, HMAC secrets, automatic AWS fallback, or anonymous production
client. Document the exact bucket access, bucket-policy inspection, signing
identity, and `signBlob` permissions needed. Production must verify uniform
bucket-level access and public-access prevention before enabling uploads. Missing
configuration/unverifiable privacy/signing failures fail closed with sanitized
503 responses. Farm/observation reads and photo-free writes remain usable when
photo storage is disabled. Health checks must not issue credentials or perform
repeated image/storage operations.

Set SDK connect/read timeouts to 5/15 seconds, at most three attempts per operation,
and a 45-second retry deadline. Signing occurs outside database locks with bounded
admission. Persist the attempt's maximum credential expiry before issuing a form;
recheck that the attempt is still current before returning it. If the signing response is lost, the durable
reservation remains replayable. No storage/decoding operation holds a farm row
lock for its duration.

Cleanup is implemented for this module's recorded attempts only. After one hour
of abandonment or terminal completion, and after every issued form has expired,
the worker may remove recorded incoming generations and unreferenced clean
attempt objects. Deletion uses generation checks and a persisted cleanup claim;
it cannot race a renewed attempt or active processing lease. With bucket
versioning enabled, clean up superseded incoming generations under that exact
recorded attempt key as well. Bound each scan; never sweep the whole bucket or
delete a ready referenced clean generation. Retries cannot delete another
attempt's objects. Retain upload/idempotency rows after object cleanup. Existing
bucket-wide retention/versioning rules stay unchanged. No cleanup is run on live
storage during implementation.

## Safety, migrations, and errors

Preserve current request IDs, log masking, strict validation, error envelopes,
and peer-IP rate limiting. Add a shared database-backed rolling limit of 30 photo
write requests per authenticated owner per minute across API instances; status
polling does not consume the photo-write quota. Use ORM locking, bounded retained
rate data, and 429 with Retry-After. Add bounded process admission so overload
returns a retryable error rather than accumulating waiting SDK/image work.

Use 401 for invalid sessions, 404 for inaccessible records, 409 for mutation or
state conflicts, 413 for excessive JSON bodies, 422 for invalid DTOs, 429 for rate
limits, and 503 for temporary dependencies/capacity. Upload processing failures
are reported by the scoped status resource using fixed codes. Document which
errors a future mobile transport should retry, pause for authentication, or mark
as permanent. No endpoint tells the phone to remove its local photo/observation.

Generate an additive Alembic revision for new bookkeeping/rate-limit tables and
indexes. Preserve existing users, identities, farms, records, and media. Enforce
new foreign keys/uniqueness with the ORM/schema; no handwritten SQL or migration
backfills that guess upload readiness. Keep existing migration lock/statement
timeouts. Rollback operationally means disabling this feature/reverting the code
while retaining its tables and data; a destructive schema downgrade is not an
automatic recovery procedure. Never migrate on API startup.

Regenerate the API client with `make client`; do not hand-edit generated output.
Document the new GCS path and limitations in upload/API documentation without
claiming the existing S3 adapter suddenly supports GCS. Include endpoint scope,
why farm creation/mobile wiring are separate, and deployment prerequisites in
the eventual PR description.

## Verification and acceptance for this slice

1. HTTP tests: missing/expired/revoked/wrong-kind tokens, forged owner fields,
   cross-owner/farm/section/media IDs, deleted parents, strict fields/body bounds,
   pagination, safe errors, request IDs, and secret-free logs.
2. PostgreSQL transaction/concurrency tests: identical observation retries yield
   one observation/mutation/change; differing fingerprints conflict; media and
   observation mutation IDs cannot collide; reservation/completion races produce
   one identity/result; independent API instances share the photo-write limit.
3. Worker recovery tests: lost completion response, intent committed before queue
   notification failure, death after claim, expired lease, stale worker result,
   cloud write before DB commit failure, pinned-generation replacement, duplicate
   jobs, bounded retries, and restart recovery without a client resend.
4. Storage adapter/sanitizer tests: signed policy exact constraints and expiry,
   missing privacy/signing configuration, wrong type/size/encoding, corrupt and
   oversized images, EXIF/GPS removal, checksum mismatch, generation-safe writes,
   cleanup races, and preservation of accepted objects. Retain S3 regressions.
5. Migration tests against disposable PostgreSQL: populated legacy schema upgrade,
   preserved identities/records, constraints, and bounded lock waits. Run the
   existing migration safety scanner and no-raw-SQL guards.
6. Run lint, typecheck, relevant unit/integration suites, generated client drift
   checks, and dependency security audit. Record failures/unavailable checks
   explicitly; do not relax checks or mark skipped tests as passing evidence.
7. Provide an opt-in staging acceptance procedure for real GCS policy/signing,
   private access, validation, retries, and one committed observation. Emulator or
   injected SDK tests do not prove GCS IAM/policy enforcement. Running it requires
   separate authorization and isolated staging resources; no live run is included
   in this approval.

The backend slice is reviewable after local/isolated evidence is recorded and
remaining staging prerequisites are explicit. Production activation still needs
GCS credentials/permissions/configuration verification and the real staging flow.
Issue 17 additionally needs mobile auth/selection/transport, device restart and
reconnect verification, and the remaining entity workflows. Do not close it or
advertise end-to-end production readiness on the strength of backend mocks.

## Reference material

- Repository: `auth.py`, `farm_records.py`, `models.py`, `uploads.py`, `tasks.py`,
  `docs/uploads.md`, `infra/gcp-staging.tf`, and PR 47's offline queue contract.
- [GCS signed policy constraints](https://docs.cloud.google.com/storage/docs/authentication/signatures)
  explain restricting an upload's destination, size, type, and expiry.
- [GCS generation preconditions](https://docs.cloud.google.com/storage/docs/request-preconditions)
  describe version-pinned operations and create-only writes. Do not assume those
  preconditions apply to multipart POST policies; they protect worker operations.
- [GCS Python client reference](https://docs.cloud.google.com/python/docs/reference/storage/latest/google.cloud.storage.client.Client)
  documents signed POST policy generation and storage client behavior.
- [GCS IAM signing prerequisites](https://docs.cloud.google.com/storage/docs/access-control/signing-urls-with-helpers)
  describe the credentials/signing permissions that must be verified before rollout.
