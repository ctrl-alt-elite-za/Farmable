# Phone-local observation/photo queue (#17 slice)

This is a local service, not a finished farmer screen or a live synchronization
feature. It does not close #17. The current app does not yet supply authenticated
farm/section selection or protected sync endpoints. Production configures **no
transport**; pending work cannot become synced merely because the phone is online.

## Integration contract

`apps/mobile/src/offline/nativeSession.ts` exports `openOfflineSession(scope)`.
Supply actual owner/farm UUIDs from the future authenticated shell. Allocate a
request with `newObservation`, retain its IDs through confirmation/retries, then
call `save`. A resolved save means the local observation and queue transaction
committed. List observations/mutations or resolve `photoUri` for local display.
The returned URI stays device-local and must not be serialized into API requests.

Only JPEG/PNG local `file:///` captures of 1–5,000,000 bytes are accepted. The
local check verifies size and signature, not full image safety: the existing
server sanitizer remains authoritative. Files are copied into app-owned document
storage; losing the camera cache does not remove a saved attachment. Do not use
SecureStore for photos or this queue. This slice relies on the OS app sandbox;
it does not claim separately encrypted media or an encrypted SQLite database.

One session owns a scope's private SQLite connection. Always await `close()`
before switching accounts/farms or opening that scope again. Closing cancels
delivery and fences late results; it does not delete pending work. No background
execution after app termination is promised. The next launch recovers interrupted
claims with the original IDs and attempt history.

A future `SyncTransport` must honor abort signals, enforce authenticated server
ownership, and preserve mutation idempotency. It receives a stable logical
payload, scoped metadata, and a separate attachment handle or acknowledged cloud
media ID. Never send local paths. Confirm the eventual HTTP contract and persist
any additional server-assigned upload/completion identifiers before enabling a
real transport; this slice does not invent those routes or claim server deduplication.
Call `setAuthenticated(true)` only when valid credentials are available, and
`credentialsUpdated()` after resolving an authentication pause.

Transient errors retry with persisted jittered backoff (2-second base,
5-minute cap, eight attempts); manual `retry` preserves IDs and total attempt
history. Conflicts are not automatically retried. A 30-second timeout aborts the
request, ignores late acknowledgements, and does not free a still-running faulty
transport to fan out more calls. Error reports contain fixed codes, not photo
contents, tokens, URLs, notes, or raw provider exceptions.

Local migrations fail closed without resetting data. There is no automatic
deletion of referenced photos, including after upload. Startup cleanup only
removes this module's temporary files older than 24 hours, before saves begin.
Final files left by a crash between file move and database commit are retained
conservatively; an operator-reviewed orphan cleanup/retention policy is future
work. App uninstall or explicit OS app-data clearing is not restart recovery.

## Automated checks

From the repository root, with the pinned Node 22 and pnpm installed:

```sh
pnpm -C apps/mobile run test --runInBand
pnpm -C apps/mobile run typecheck
pnpm run lint
```

Queue tests use Node's real SQLite engine and disposable real files, not a
handwritten SQL mock. They cover transaction rollback, scoped access, reopen
recovery, upload dependencies, retry budgets, stale replies, and no-data-loss
failures. These checks do **not** replace tests of Expo's native adapters.

## Native restart probe (Android and iOS separately)

Build a development client with `EXPO_PUBLIC_TEST_MODE=1` and demo mode unset.
The added native dependencies require a new native build, not an OTA-only update.
In React Native DevTools' console, choose a new run UUID and invoke:

```js
await globalThis.farmableOfflineProbe('seed', 'abcdef01-2345-4678-89ab-cdef01234567');
```

Do this without network connectivity. Expect `saved_locally`. The probe writes
one synthetic PNG, saves an observation and two queue entries, deliberately
leaves an in-progress claim, and removes only its synthetic original capture.
Terminate the app without clearing its data, relaunch, reconnect DevTools, then:

```js
await globalThis.farmableOfflineProbe('verify', 'abcdef01-2345-4678-89ab-cdef01234567');
```

Expect `restart_and_failed_upload_preserved`. Inspect the returned local URI on
the device to confirm the photo remains viewable. The probe uses no network
transport: it injects an upload failure and verifies retained data. Its separate
database and media directories contain only synthetic fixtures. Use a new UUID
for another run; fixtures are retained for inspection. The function is unavailable
outside test mode, and refuses test/demo combinations.

Record platform, device/OS, commit, both probe outputs, and actual termination
steps when reporting acceptance. Until those steps run, native restart/media
viewing is **not verified**. A fake transport test is not evidence of exactly
one observation on a real server. Authenticated reconnect/media integration and
the other entity workflows remain outstanding on issue #17.
