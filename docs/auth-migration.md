# Authentication migration and recovery

PR 44 adds authentication storage without altering the existing `users` table.
Revision `0004` creates `auth_identities`, `verification_challenges`, and
`auth_sessions`. An identity shares the user's UUID, so existing farm ownership
does not change. Legacy users are preserved without invented passwords or
verification flags. New signups create a user and its identity in one transaction.

All unique indexes and check constraints are built on the new, empty tables.
Creating their foreign keys still requires short metadata locks. Alembic uses a
one-second lock timeout and a five-second statement timeout, configured on its
PostgreSQL connection; application connections keep their existing settings.
This is not a claim of zero locking or a guarantee of deployment latency.

## Deployment

Back up the database, review the migration, and apply it explicitly before
deploying the new backend. The database must be at the main branch's revision
`0003`. A timeout aborts the transaction: tables and the Alembic version update
roll back together. Investigate the blocking transaction, then explicitly retry
the migration. Do not disable timeouts or blindly retry while contention persists.

The offline SQL scanner cannot see connection-startup settings and may still
report `require-lock-timeout` and `require-statement-timeout`. Those warnings
remain visible for maintainer review. PostgreSQL integration tests verify the
effective settings and the lock-timeout/rollback/retry path. No scanner rules are
disabled, and this change does not apply a `migration-approved` label.

The former, unmerged version of `0004` put credentials directly on `users`.
A private database that already applied that version needs a separate,
data-preserving operator migration plan. Do not re-stamp its version, reset it,
or assume that running `upgrade head` converts that old layout.

## Rollback

For an application rollback, retain the new auth tables and restore the previous
backend release. Existing users and farms remain compatible. An explicit schema
downgrade to `0003` deletes credentials, verification challenges and sessions;
use it only when that data loss is intended and backed up. It preserves the
ownership records, but it is not the normal live application rollback procedure.

Live OTP delivery and mobile authentication remain separate issue-9 work. This
change does not enable providers, deploy to GCP, or merge PR 44.
