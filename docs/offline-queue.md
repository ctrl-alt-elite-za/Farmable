# Durable Flutter observation/photo queue (#17)

PR #47 preserves the Flutter app from main: design system, seed, Home and Zone
Detail journeys, Drift database, Android/iOS projects and Flutter CI. No Expo
replacement, new runtime dependency or second local database is introduced.

## Scope

This began as the local queue foundation. The live transport, lifecycle and
photo capture now exist — see [Live sync](#live-sync-17) below. Being online
never marks a record synced: only a matching server acknowledgement does.
The demo farm is never sent at all.

In `apps/mobile/lib/data/local/`:

- `sync_outbox.dart` keeps immutable observation snapshots and scoped delivery
  bookkeeping on the **existing `sync_mutations` outbox**.
- `sync_runner.dart` provides optional transport, serial delivery, cancellation,
  acknowledgement checks, bounded retries and explicit readiness inputs.
- `offline_photos.dart` provides durable app-owned files and an idempotent
  service for saving a new observation with an optional attachment.

Existing `LocalFarmRepository` observation create/edit/delete calls enqueue a
snapshot in the same transaction as the record write. Home and Zone Detail
continue reading the same records and showing their pending state. Other
record types stay in the outbox, but this runner does not send them.

## Storage and migration

Schema v2 adds delivery columns to `sync_mutations` and a `local_photos` table.
The v1 farm, sections, observations, tasks, projections, seed marker and mutation
IDs are preserved. There is no destructive migration/reset fallback.

Old mutations have no historical payload. They remain pending with a null
payload and are not sent: reconstructing an old mutation from today's record
would change its meaning. Newer mutations depend on their predecessors, so a
legacy predecessor also blocks them. Future reconciliation must address this
explicitly, not pretend those changes reached the server.

New observation mutations keep their own payload and version. Creates, edits
and tombstones are ordered through dependencies, even with identical clocks.
An acknowledgement only marks the matching local version synced; an edit made
during a send stays pending. Failed/conflicted predecessors block dependants,
not unrelated records.

## Integration

Use the app's existing `AlmanacDatabase`; do not open another connection for the
same file. Obtain owner/farm UUIDs from the eventual authenticated session;
demo seed IDs are not credentials.

1. Construct `SyncOutbox(db, ownerId: ..., farmId: ...)`.
2. Await `OfflinePhotos.onDevice` for that scope, then `photos.recover(now)`
   before saves begin.
3. Construct `OfflineObservations(outbox, photos)`. Allocate observation,
   mutation and optional photo/upload UUIDs **before** confirmation and retain
   them on save retry. Changed content under one mutation ID is rejected.
4. `SyncRunner.open(outbox, photoUri: photos.view, transport: adapter)` recovers
   interrupted claims and watches the outbox. Transport is optional; the demo
   does not construct a fake adapter.
5. Feed real connectivity, foreground lifecycle and credential readiness into
   `setConditions`. All three must be true. After credential refresh, call
   `credentialsUpdated`.
6. Await `stop()` before switching accounts/farms or closing storage. An adapter
   ignoring cancellation prevents a replacement runner on that database until
   its outstanding send settles. Do not bypass this with another connection.

Acknowledgements must match mutation, record, owner and farm IDs. Media acks
also require a cloud UUID, stored before the dependent observation is claimed.
Upload URI and cloud ID are separate delivery fields; local paths never enter
the JSON payload. A real adapter must translate snapshots into the API contract
and durably retain reservation/finalization identities before retrying. That
adapter and conflict resolution are follow-up work, not implicit guarantees.

## Delivery and files

- One physical send at a time; a 30-second deadline cancels timed-out IO. Late
  results cannot acknowledge released work or cause retry fanout.
- Transient errors back off with jitter (2-second base, 5-minute cap), at most
  eight automatic attempts. Manual retry only applies to failed work: it resets
  the budget, never mutation ID, payload or lifetime attempt count.
- Auth failure pauses until credentials change. Background/offline/stop fences
  active results and refunds the cancellation's retry budget.
- Conflicts never retry blindly. Diagnostic callbacks carry fixed codes, not
  raw errors, notes, tokens or paths. Delivery failure state is in the outbox;
  the existing record/UI stays pending until its matching acknowledgement.
- JPEG/PNG captures must be 1–5,000,000 bytes with the expected signature. This
  precheck does not replace server image decoding/sanitization.
- Copy to application documents, validate and flush, then rename before the
  database commit. The caller's camera/cache file is never deleted.
- Referenced photos remain after acknowledgement. Ambiguous orphan copies are
  retained. Startup cleanup only removes expired `.tmp` files; it is not a
  general photo garbage collector.

## Verification

From `apps/mobile`, with the pinned Flutter SDK:

```sh
flutter pub get --enforce-lockfile
dart run build_runner build
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --exclude-tags demo-api
```

From the repository root, run the separate live-contract suite with its
disposable backend: `uv run python scripts/test_mobile_contract.py`.

`sync_outbox_test.dart` uses real SQLite, including file-backed reopen and v1
migration. `sync_runner_test.dart` covers readiness, retries, auth pause,
conflicts, deadlines, cancellation and late acknowledgements. Fake-transport
tests are not evidence of cloud uploads or physical-device performance.

## Live sync (#17)

In `apps/mobile/lib/data/sync/`:

- `api_sync_transport.dart` — the `SyncTransport` over dio and the logged-in
  session (`ApiAuthService.authorized`, bound to the session generation the
  runner opened under). Observations: `ObservationCreate`, `ObservationUpdate`
  and `RecordDelete`, with `expected_version` = the outbox row's version − 1.
  Photos: reserve → multipart POST of the form fields plus the file to the
  signed form (never with the bearer token) → complete → bounded status polls
  (1, 2, 4, 8, 15 s) → `ready`. An expired or refused form is renewed by an
  exact replay of the reservation, which returns the same upload and media
  identity. A retryable failure waits for the farmer's "Try again", which
  permits exactly one `/retry` naming that attempt.
- `account_workspace.dart` — `GET /farms` names the account's farm; it and the
  account's sections (`GET /farms/{id}/sections`) are stored locally under the
  signed-in user's id.
- `sync_controller.dart` — opens the runner for the signed-in account's farm,
  feeds it connectivity (`connectivity_plus`), foreground state and the
  session, and awaits `stop()` on logout or account switch.

### Demo farm vs. real accounts

Separation is by ownership. Every local row carries `owner_id`; the demo
seed's is a constant (`DemoSeed.ownerId`) the workspace refuses as an account
id. The runner's outbox is scoped to *(signed-in user id, farm id from
`GET /farms`)*, so it can never claim a demo row or another account's row, and
the screens (`LocalFarmRepository(ownerId: …)`) read only the active scope.
Signed out, the phone shows the demo; signed in, the account's farm. A record
written while signed out stays in the demo farm and is never re-owned.

On logout the previous account's farm leaves the screen immediately, its
runner is stopped (awaiting any send in flight), and its queued rows and
photos stay on the phone — unsent and unshown — until that account signs in
again. Photo files live under `photos/{owner}/{farm}/`, and `OfflinePhotos`
refuses any other scope.

### Records, states and files

- Observation tiles show queued · sending · sent · not sent yet (with "Try
  again") · changed on another phone (no blind retry). Each has a stable
  accessibility id `record-delivery-<state>` for E2E flows.
- The observation form can attach one photo (the back camera; the bundled
  test picture in `TEST_MODE` builds, labelled as such). Ids are minted when
  the form opens, so a repeated Save is the same observation and photo.
- The phone's copy of a photo is deleted only after the server reports it
  `ready` and the acknowledgement has committed (`releaseUploaded`).
- Schema v4 adds `upload_id`, `failed_attempt_id`, `recover_attempt_id` and
  `purged_at` to `local_photos`.

### Not yet synced

Only observations and photos are sent. Sections, plantings, tasks, financial
records and saved plans remain queued with null payloads, as before. The
change feed (`GET /farms/{id}/changes`) is not pulled; sections are re-read on
sign-in, reconnect and return to the foreground. `e2e/mobile/upload_offline_resume.yaml`
needs a stack with photo storage, which `scripts/ci-stack.sh` does not
configure (see the flow's header).
