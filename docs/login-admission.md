# Login admission recovery

Login verification reserves a random request lease in both the hashed account
and IP counters. Each lease expires after 60 seconds; at most 32 are active per
bucket. A worker crash or database error therefore cannot permanently consume
capacity. No periodic cleanup worker is needed to recover admission.

Completion removes only its own lease and checks that it is still valid in both
buckets. Expired, missing or already-finished requests cannot issue a session or
release another request's capacity. Failure counts retain their independent
15-minute window; lease expiry does not clear a password lockout. Session writes
and the final lockout check remain in one database transaction.

Apply migration `0024` after `0023`, with independent migration review. Drain and
stop old API workers before running the new version: legacy workers only maintain
an integer counter and cannot participate in lease fencing. New code recomputes
that compatibility counter from the lease map; it preserves existing failure
hits. For downgrade, drain login traffic first; removing the lease column removes
this recovery/fencing protection. No migration runs automatically at API startup.

SQLite tests cover expiry and stale completion, while the existing PostgreSQL
integration selection runs parallel admission/accounting tests in
`test_auth_postgres.py`. Neither suite proves live OTP delivery.
