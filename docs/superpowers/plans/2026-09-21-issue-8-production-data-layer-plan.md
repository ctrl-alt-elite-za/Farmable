# Issue 8 production data-layer implementation plan

1. Harden the ORM and Alembic schema together.
   - Add reusable ownership, revision, value, text-length, and state constraints.
   - Add composite tenant foreign keys and query-path indexes.
   - Add mutation request fingerprints and a monotonic change cursor.
   - Keep model/migration parity tests exact.
2. Harden repository behavior.
   - Require owner and farm scope.
   - Canonically fingerprint observation mutations.
   - Reserve mutations inside savepoints and recover exact concurrent replays.
   - Lock tombstoned records and map integrity failures to domain conflicts.
   - Move deterministic seed data to a dedicated module.
3. Expand verification.
   - Update fast acceptance tests for exact replay and scoped queries.
   - Add PostgreSQL integration tests for tenant constraints, concurrent replay,
     tombstone retry, ordered changes, and seed idempotency.
   - Keep migration autogeneration empty and migration lint explicitly reviewed.
4. Validate and hand off.
   - Run formatting, lint, types, unit tests, raw-SQL scan, client freshness,
     migration safety with local approval, and Docker integration tests.
   - Push the branch, update PR #42 with hardening and migration-review details,
     and leave approval/merge to another reviewer.
