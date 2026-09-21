# PR 44: live-database authentication safety fixes

## Scope and decision

Fix the event-loop blocking, duplicate-signup race, and migration locking risks
identified in PR 44. Keep its API contract unchanged and leave the PR unmerged,
with auto-merge disabled. Do not add mobile authentication, live OTP delivery,
access-token middleware, or alter any deployed database.

The requester selected the live-database approach over a maintenance-window
migration. Since authentication has not merged, the smallest implementation is
additive credential storage rather than a multi-phase alteration of `users`.
The latter needs concurrent index builds, constraint validation, and recovery
from partially applied phases. A new credential table avoids those scans while
preserving the existing ownership model.

## Authentication execution

Keep asynchronous HTTP handlers but offload each complete synchronous auth
service call to the worker thread pool. A per-app limit of two active auth calls
bounds password-hashing memory/concurrency; waiting for a slot must not block the
event loop. Sessions remain created and used inside the service call on that
worker. Existing error envelopes and request correlation remain intact.

## Duplicate signup

Keep the friendly existence check, but treat database uniqueness enforcement as
authoritative. Catch only PostgreSQL unique violations for the named email and
phone constraints and translate them to `409 account_exists` after transaction
rollback. Propagate unrelated integrity errors. The losing request must leave
no orphan user, identity, challenge, or delivered OTP.

## Additive migration

Restore `users` to its existing identity/ownership shape. Introduce
`auth_identities` with its primary key referencing `users.id`, required account
fields, unique email/phone constraints, and verification flags. Move credential
queries and row locks to this model; create the user and identity atomically.
Challenges and sessions reference the identity and cascade through it when a
user is deleted. Existing users and farms receive no invented credentials and
remain unchanged.

Rewrite only the unmerged `0004` migration to create the three new auth tables,
their constraints and indexes. Do not edit migrations already on main. Restore
the existing migration-0003/users schema-parity test. Use a 64-bit attempts
counter consistent with migration lint requirements.

Migration connections retain the existing five-second statement timeout and
gain a one-second lock timeout. Apply these via connection settings, without
handwritten SQL or disabling safety rules. New foreign keys still require short
metadata locks: this design avoids long scans, not all locking. Contention must
abort and roll back the migration, allowing an explicit retry after the blocker
is gone. Do not automatically retry tests or apply the migration-approved label.

The new migration applies from deployed main's revision `0003`. Any private
database that already ran the former unmerged `0004` requires an explicit
operator migration plan; it must not be silently rewritten or reset.

## Verification

- Prove health requests can complete while auth calls are deliberately blocked,
  and prove no more than two auth calls run at once.
- Reproduce simultaneous duplicate-email and duplicate-phone signups against
  disposable PostgreSQL; assert one success, one 409, and no orphan records.
- Prove unrelated integrity failures are not misreported as account conflicts.
- Upgrade a disposable database containing revision-0003 users/farms; verify
  their values and relationships survive and the ORM matches the new schema.
- Exercise migration lock contention, rollback, and a subsequent explicit retry
  on a disposable database. No live database changes are authorized.
- Run authentication, backend and script tests, formatting, lint, type checks,
  generated-client validation, no-raw-SQL, migration-safety and integration CI.
- Publish findings and verification on PR 44 without merging it.

## Working checklist

- [x] Explore repository, review findings, and migration constraints.
- [x] Clarify live-database versus maintenance-window requirements.
- [x] Compare migration approaches and select additive storage.
- [x] Present the design and write this specification.
- [x] Self-review scope, failure handling, and verification requirements.
- [x] Requester reviews the written specification.
- [x] Produce implementation plan and implement the approved design.
- [x] Verify locally, including isolated PostgreSQL migration and race checks.
- [ ] Push without merging and inspect CI; retain the migration-review gate.

No visual companion is needed for these text-only decisions. The referenced
writing-plans skill is not installed; after specification approval, use the
verification list above to write a concrete implementation plan directly.

## Implementation sequence

1. Add the failing health/auth concurrency regression, then offload service calls
   to a dedicated two-worker executor with request-context propagation.
2. Introduce the credential model and rewrite pending `0004` additively; keep the
   ownership model unchanged and bound migration connection lock waits.
3. Handle only named credential uniqueness violations after rollback; test both
   concurrent signup conflicts and unrelated database errors.
4. Test schema parity, existing-record preservation, and migration contention in
   disposable PostgreSQL. Run local checks and CI, then publish the fixes with
   migration-review limitations explicit. Do not merge or enable auto-merge.
