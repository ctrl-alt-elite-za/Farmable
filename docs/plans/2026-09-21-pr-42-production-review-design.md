# PR 42 production review design

## Goal

Make the per-farm synchronization cursor safe under concurrent PostgreSQL
commits without changing the public record schema.

## Design

PostgreSQL identity values are allocated before transaction commit. Without
serialization, a client can observe a higher committed cursor and permanently
skip a lower cursor that commits later. Before reserving a new mutation, the
repository will lock the owned farm row and then re-check the idempotency key.
This orders change-producing transactions within one farm while allowing
different farms to proceed independently.

Exact mutation retries continue to return the original result. Cross-request
mutation reuse continues to fail closed. A PostgreSQL concurrency regression
test will prove that a second same-farm write waits and that committed change
cursors are observed in order.

## Verification

Run unit and PostgreSQL integration tests, migration-safety verification,
formatting, linting, type checking, and the repository verification suite.
