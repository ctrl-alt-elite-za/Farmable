# Issue 8 production data-layer hardening

## Purpose

Finish issue #8 as a production-grade persistence and synchronization foundation. The change remains limited to domain models, migration `0003`, the repository boundary, deterministic demo seeding, and data-layer tests.

The definition of done is the issue #8 acceptance criteria plus database-enforced tenant integrity, concurrency-safe mutation replay, deterministic conflict handling, and proof against PostgreSQL 16/PostGIS rather than SQLite alone.

## Scope

### In scope

- The required `User`, `Farm`, `Section`, `Planting`, `Observation`, `FarmTask`, `FinancialRecord`, `Media`, `SavedPlan`, `SyncMutation`, and `SyncChange` records.
- UUIDs created by clients before synchronization.
- Owner and farm isolation, timestamps, revisions, sync states, and tombstones.
- An append-only mutation ledger and ordered change feed.
- Observation creation/deletion behavior needed to prove replay safety.
- A deterministic, explicitly invoked demo seed.
- Alembic/ORM parity and PostgreSQL integration coverage.

### Out of scope

- Authentication, sessions, authorization middleware, or row-level security from #9.
- HTTP routes, generated API clients, and full feature CRUD from #11.
- The on-phone queue, retry scheduler, upload lifecycle, and conflict UI from #17.
- A generic sync protocol for every future entity.
- Marketplace, advanced analytics, and animal-health records.
- Final GeoJSON/PostGIS boundary interchange. `Section.boundary` remains JSON until #11/#15 define the production API contract; this PR must not guess that contract.

## Data model and integrity

All farmer-created records use client-safe UUID primary keys. System change-feed entries use a monotonic `BIGINT IDENTITY` primary key so clients can later request changes after a stable cursor.

The database, not only repository code, enforces the ownership hierarchy:

- A farm belongs to one user and exposes a unique `(id, owner_id)` key.
- A section references its farm through `(farm_id, owner_id)` and exposes a unique `(id, farm_id, owner_id)` key.
- Every owned child references `(farm_id, owner_id)` with cascade-on-farm-removal. Section links additionally reference `(section_id, farm_id, owner_id)` through a deferred `NO ACTION` constraint. This permits a whole account/farm cascade to complete atomically but rejects direct physical section deletion while child records remain; farmer deletion uses tombstones.
- An observation's optional media reference must resolve within the same owner and farm.

This deliberately duplicates `owner_id` and `farm_id` on synchronized rows. The values make tenant filtering and offline conflict diagnosis cheap, while composite constraints prevent them from drifting apart.

Reusable constraints enforce:

- revisions greater than zero;
- positive section area when present;
- nonnegative financial amounts and expected costs;
- allowed sync/task/plan/financial states;
- nonblank farm/section names and task titles bounded to 200 characters;
- crop, category, record-type, health, and media-type values bounded to 100 characters, with operations and statuses bounded to 20;
- local media IDs bounded to 255 characters, object keys to 1,024 characters, and notes/descriptions/actions to 10,000 characters;
- at most one nondeleted current planting per section;
- one globally unique mutation ID and a valid SHA-256 request fingerprint.

JSON values use PostgreSQL `JSONB` with a portable JSON fallback for unit tests. JSON structure remains an API-schema responsibility in #11; this PR only stores the existing boundary and plan snapshots.

Indexes follow known access paths: active records by owner/farm, section observations by creation time, section tasks by due date, section finances by date, mutation lookup by key, and changes by farm/cursor.

## Repository boundary

`FarmRecordRepository` is initialized with both `owner_id` and `farm_id`. Every lookup includes both values and hides tombstoned rows unless the operation explicitly needs a tombstone. It never commits; transaction ownership remains with the caller.

Demo seed construction moves to a dedicated module so production repository code has no fixture constants or dates.

Invalid or conflicting operations raise stable domain exceptions. Database integrity errors are handled inside nested transactions so a rejected operation does not poison the caller's outer transaction or leak database details.

## Mutation and change flow

Each mutation is canonically serialized from its operation, entity type, client record ID, target section, and normalized payload. Only its SHA-256 fingerprint is stored; notes and other farmer data are not copied into the mutation ledger.

For a new observation mutation:

1. Check for an existing ledger row by `mutation_id`.
2. If found, compare owner, farm, operation, record ID, and fingerprint.
3. Return the original logical record only for an exact match; otherwise raise `RecordConflictError`.
4. If absent, enter a savepoint and insert the mutation ledger row first. The unique key serializes concurrent attempts.
5. Validate the owned section and optional media, create the observation, and append exactly one `SyncChange` before releasing the savepoint.
6. If another transaction won the mutation key race, roll back only the savepoint, reload the winner, and apply the exact-replay rules.

Deletion follows the same ledger-first flow and locks the owned observation row before changing its tombstone and revision. A retry returns the same tombstone without incrementing its revision or appending a second change.

`SyncChange` is immutable and ordered by its identity cursor. Each row records owner, farm, mutation, entity type, entity ID, operation, resulting revision, and database creation time.

## Migration safety

Migration `0003` remains the single new Alembic revision and may be corrected while PR #42 is unmerged. After merge it is immutable: later changes require a new revision. Model and migration declarations must be structurally identical, and an unchanged schema must autogenerate an empty migration against PostgreSQL.

The migration creates new tables and indexes only; it does not rewrite existing application tables or touch provider-owned schemas. Squawk warnings and the generated SQL are documented in the PR. Local verification may set `CI_MIGRATION_APPROVED=true`, but the PR remains blocked until a different maintainer reviews the SQL and applies `migration-approved`.

No handwritten SQL, `op.execute`, raw cursor, or application-startup migration is introduced.

## Tests

Fast unit tests continue to cover the issue acceptance cases and canonical fingerprint behavior. PostgreSQL integration tests additionally prove:

- all migration constraints and foreign keys are active;
- a mismatched owner/farm/section/media relationship is rejected;
- concurrent sessions replaying the same mutation create one observation, one ledger row, and one change row;
- reusing a mutation ID with a different payload or owner is rejected;
- retrying a tombstone does not increment its revision twice;
- a failed mutation leaves the outer session usable;
- the change cursor is strictly increasing;
- repeated demo seeding is safe and does not duplicate records;
- Alembic and ORM metadata remain identical.

Repository-wide lint, formatting, typing, unit, integration, security, migration, deployability, generated-client, and mobile checks must remain green. No test may weaken or bypass a production constraint for SQLite convenience.

## Acceptance mapping

| Issue criterion                                   | Proof                                                                                     |
| ------------------------------------------------- | ----------------------------------------------------------------------------------------- |
| Client-generated UUID accepted                    | Unit and PostgreSQL repository tests preserve the supplied record ID.                     |
| Duplicate mutation does not duplicate observation | Sequential and concurrent exact-replay tests assert one record, ledger entry, and change. |
| Observations are owner-scoped                     | Composite constraints plus repository queries and cross-owner tests.                      |
| Tasks are owner-scoped                            | Composite constraints plus repository queries and cross-owner tests.                      |
| Financial records are owner-scoped                | Composite constraints plus repository queries and cross-owner tests.                      |
| Tombstone is not resurrected                      | Create/delete/recreate and repeated-delete tests.                                         |
| Demo seed has observations and tasks              | Idempotent seed test on PostgreSQL and fast unit coverage.                                |

## Review and rollout

PR #42 remains the single review vehicle. The implementation updates its branch instead of opening a conflicting PR. The PR body will distinguish issue acceptance from production hardening, list the exact migration warnings, and give reviewers commands for the focused and full verification suites.

Merging #8 only makes the data layer available. It does not claim authentication, production endpoints, phone-side persistence, or end-to-end synchronization are complete.
