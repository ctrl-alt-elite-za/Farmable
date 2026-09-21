# Issue 17: durable mobile observation and photo queue

## Scope and approved decisions

Implement the first, independently useful slice of issue #17 on the current
Expo/React Native app, starting from main `7f58777`. The requester approved
starting with the durable phone queue and a narrowly scoped mobile SQLite
exception to the repository's SQLAlchemy-only rule. Backend rules remain intact.

This slice provides local observation/photo persistence and a restart-safe queue
with a testable synchronization interface. It does not close issue #17. Protected
server endpoints, server-side mutation deduplication, mobile authentication,
farmer-facing observation screens, other entity workflows, and live uploads are
separate integration work. Do not invent farm ownership or send unauthenticated
requests to make the queue appear operational. Do not merge PRs, enable
auto-merge, deploy, or modify any live database.

The app currently has health and native self-test screens, not a farmer
observation flow. Deliver a reusable local service and native test harness, not
a replacement app or a claim that farmers can already synchronize observations.

## Alternatives and selected approach

1. **SQLite plus app-owned photo files (selected):** transactionally persist an
   observation and its queue entries together; use explicit recovery for the
   separate filesystem operation. Requires a mobile native dependency and the
   approved repository-rule exception.
2. **File-based journal:** avoids a database dependency but requires custom
   indexing, transactional updates, compaction, and crash recovery.
3. **Wait for server endpoints:** simplifies immediate integration but prevents
   independent progress on local durability and restart recovery.

Use the Expo-SDK-compatible `expo-sqlite` release, not an Expo SDK upgrade. Add
the exception to `AGENTS.md` only for the phone-local queue implementation and
its tests. Permit fixed local schema statements and parameter-bound queries
there; forbid interpolated user input, dynamic user-selected SQL identifiers,
and database calls from UI components. Do not relax Python/raw-SQL checks or
permit handwritten backend SQL.

## Components and persistence

Keep the implementation under `apps/mobile/src/offline/` with separate modules
for validated data types, SQLite persistence, photo storage, queue execution,
and lifecycle control. Inject clocks, UUID generation, connectivity, and the
sync transport for deterministic tests. Use native-safe random UUIDs; never
derive identifiers from timestamps or `Math.random()`.

The local store contains observations, media metadata, mutations, and a local
schema version. Every record and query is scoped by explicit owner and farm
UUIDs. Observations also require a section UUID. This scope is a local isolation
boundary, not a substitute for server authorization. A missing active identity
must not select another owner's data or start network work. No tokens or
passwords belong in these tables or logs.

Observation fields follow the existing model: UUID, owner/farm/section,
type/note, optional health status/action, local media reference, voice flag,
timestamps, version, and sync state. Validate required values and UUIDs at the
service boundary; retain backend text limits and cap serialized mutation payloads
at 64 KiB. This slice supports creation and reading;
editing, deletion/tombstone propagation, tasks, finance, sections, and approved
plans remain follow-up workflows rather than unvalidated generic payloads.

Each mutation persists the issue's required fields: `mutation_id`,
`entity_type`, `entity_id`, `operation`, `payload`, `created_at`,
`attempt_count`, and `sync_state`. Add owner/farm scope, next-attempt time,
dependency reference, and a bounded error code. Support only observation-create
and photo-upload operations in this slice. A retry retains the same mutation ID
and immutable logical payload. Re-enqueuing the same ID and identical payload
returns the existing result; a different payload for that ID is rejected.

Serialize writes through one store instance and use exclusive transactions
for atomic observation/media metadata/queue changes. No file copy or network
call holds a SQLite transaction open. Use versioned transactional migrations,
foreign-key enforcement, and explicit connection ownership/cleanup. Migration,
storage-full, or corruption errors fail visibly without resetting the database
or claiming a successful save. Native Android/iOS are supported; a web memory
fallback must not masquerade as durable storage.

## Saving and retaining photos

Accept a local captured-photo URI; camera UI is outside this slice. Copy the
photo into the app's persistent, private document storage under generated IDs,
not a cache directory. Persist a relative path, resolving the current document
root when reading. Accept JPEG/PNG files of 1–5,000,000 bytes, matching the
existing storage slice; reject unsupported files and oversized inputs with clear
errors. Do not fetch arbitrary remote URIs. Local acceptance does not replace
the server's image validation and sanitization.

Copy into a uniquely named temporary file, complete the move to its final
app-owned path, then commit the observation, media metadata, and upload/create
mutations in one SQLite transaction. Only a committed save may be reported as
saved locally. If copying fails, report failure and preserve the original input;
offer a separate explicit no-photo save through the service, never silently
discard the attachment. On a database failure, remove only the unreferenced
file created by that operation. Startup recovery may remove stale unreferenced
temporary files older than 24 hours in this module's own directory, with no
concurrent save active;
never delete an original capture or a referenced attachment.

Because files and SQLite cannot commit together, test every crash boundary.
Referenced media remains readable offline after reopening. A failed upload or
missing local file never deletes the saved observation. Missing files produce a
visible failed-media result. Automatic deletion of referenced media, including
after upload, is out of scope; no silent eviction of unsynced data.

## Queue execution and recovery

Implement the five states from #17: `pending`, `syncing`, `synced`, `failed`,
and `conflict`. Claim due work transactionally, with at most one active transport
call. Multiple wakeups share one runner. A controller owns the store lifecycle;
closing or switching identity stops scheduling and invalidates stale callbacks.
Only after the previous runner has stopped may reopening recover interrupted
`syncing` rows to `pending`, retaining IDs, payloads, and attempt history.

The controller wakes at startup, foreground resume, connectivity restoration,
or the next persisted retry time while active. No promise of OS background
execution after the app is killed. Offline, missing credentials, or an absent
transport leaves work pending without consuming attempts. Use a 30-second
transport deadline and an abort-aware transport contract. Ignore late responses
after timeout, shutdown, or scope change; never let them mark work synced.

Transient failures use persisted exponential backoff with jitter: a 2-second
base, 5-minute cap, and at most eight automatic attempts before `failed`.
Manual retry resets the automatic budget but preserves mutation identity and
payload. Validation failures become `failed`; version/idempotency conflicts
become `conflict` and require explicit resolution in later integration work.
Authentication failures pause delivery until identity credentials are restored.
Do not use last-write-wins or silently overwrite a conflict.

An observation depending on a photo remains locally visible while its delivery
waits for the upload result. An unrelated observation must still be eligible.
Persist media acknowledgement and its cloud ID before releasing the dependent
mutation. Local paths are never included in a network payload.

Define a typed transport interface, not speculative HTTP routes. A transport
receives the stable logical mutation and returns a validated acknowledgement or
classified failure. Responses must match the expected mutation/entity/scope
before marking work synced. Production has no configured transport until a
reviewed authenticated API contract exists; only tests use a fake transport.
The future HTTP adapter must preserve idempotency across lost acknowledgements
and stable media-ID mapping. A local queue cannot guarantee exactly one server
record without server-side deduplication.

## Verification and delivery

- Unit tests cover validation, scoped reads/writes, duplicate local enqueue,
  transaction failure, retry limits, persisted deadlines, conflict/auth handling,
  upload dependencies, concurrent wakeups, cancellation, and identity switching.
- Storage tests use a real SQLite engine for transactions, constraints,
  migrations, reopen recovery, and failures. Mock-only tests are insufficient
  evidence of durability.
- A test-build native harness exercises the actual Expo SQLite/filesystem
  adapters: save without network, terminate/relaunch without clearing app data,
  read the same observation/photo, recover pending work, and simulate upload
  failure without data loss. Test fake acknowledgements separately from any
  claim of server synchronization. Never contact a paid/live provider.
- Run mobile tests, type checks, lint/format checks, and applicable repository
  checks. Record actual Android/iOS coverage; an Android emulator does not prove
  iOS durability. If a native platform cannot be exercised, state that limitation
  and keep its acceptance unverified.
- Deliver the slice for review without merging. Issue #17 remains open until
  authenticated endpoints, real reconnect synchronization, and exactly-one-server
  observation acceptance are verified end to end.

## Working checklist

- [x] Inspect issue, existing storage work, main branch, mobile app, and rules.
- [x] Clarify independent queue scope and approve the mobile SQLite exception.
- [x] Compare SQLite, a file journal, and deferring until server integration.
- [x] Present the local durability approach and write this specification.
- [x] Self-review scope, crash recovery, account isolation, and acceptance claims.
- [ ] Requester reviews the written specification.
- [ ] Produce implementation plan, implement, verify, and publish for review.

No visual companion is needed for these storage decisions. The referenced
writing-plans skill is not installed; after written-spec approval, write the
implementation plan directly using the verification requirements above.

## References

- [Issue #17](https://github.com/ctrl-alt-elite-za/Farmable/issues/17)
- [Existing photo storage boundary](../../uploads.md)
- [Expo SDK 57 SQLite documentation](https://docs.expo.dev/versions/v57.0.0/sdk/sqlite/):
  persistent storage, parameter binding, exclusive transactions, native/web
  differences, and SDK-compatible installation.
