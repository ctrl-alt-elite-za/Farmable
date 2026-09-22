# Issue 17 authenticated sync API implementation plan

Approved specification: `../specs/2026-09-21-issue17-authenticated-sync-api-design.md`.
No merging, deployment, live migration, or live storage operations.

1. Add upload/attempt/rate ORM models and an additive migration; test constraints
   and populated-database migration compatibility.
2. Add bearer-session authorization, strict DTOs, bounded authenticated routes,
   owner-scoped keyset reads, and retry-safe observation writes. Test negative
   authorization cases and idempotency before connecting storage.
3. Add transactional upload reservation, completion, status, owner-wide rate
   limiting, processing claims, and fenced finalization/recovery.
4. Add the GCS adapter with IAM signing, private-bucket verification, bounded
   generation-pinned reads, sanitizer reuse, and create-only clean writes.
5. Run durable-intent processing and bounded cleanup in the existing worker;
   test crashes, stale claims, retries, expiry/reopening, and cleanup races.
6. Regenerate the API client; document operation contracts, structural limits,
   configuration/IAM prerequisites, and opt-in staging acceptance.
7. Run local lint/typecheck/unit checks, disposable PostgreSQL integration and
   migration tests, migration safety, generated client drift, and security audit.
   Record actual evidence and limitations. Review the diff before committing.

The writing-plans skill is unavailable; this checked-in plan is the fallback.
Do not call the issue complete or claim real GCS/native acceptance from mocks.
