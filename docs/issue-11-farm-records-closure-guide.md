# Issue #11 closure guide: farm records REST and sync API

This guide is the reviewer and client-integration contract for issue #11. The
implementation is already present in the PR #72 stack through the merged farm
records work; this document makes the behavior explicit and records how to
verify it without replaying the implementation commits.

## Stack relationship

PR #72 is the parent stack. The farm-record implementation was merged earlier
by PR #59 and is an ancestor of PR #72's head. A stacked closure PR therefore
must contain only this contract guide and the `Closes #11` reference. It must
not copy the records routes, repositories, or generated client files again.

Useful checks when reviewing the stack:

```sh
git merge-base --is-ancestor issue-11-backend-rest-and-sync-api origin/pr-72-head
git diff --stat origin/pr-72-head...HEAD
```

The first command must succeed. The second should show only the closure
artifact (and any deliberately related documentation change).

## Authentication and tenant isolation

All routes use the verified access token from `/auth/login`:

```http
Authorization: Bearer <access-token>
```

The API derives the owner from the session. Clients never send an owner ID and
must not use a refresh token as a bearer token. Every farm, section, record,
cursor, mutation, and media reference is checked against that owner and farm.
Missing and foreign IDs resolve to the same `404 not_found` response so an
attacker cannot probe another farm.

Request bodies reject unknown fields and are bounded by the API admission
middleware. Stable error responses use the common shape and a machine-readable
`error.code`; clients should reconcile `409` conflicts rather than retrying a
changed mutation automatically.

## Resource routes

The production API scopes records under a farm. The issue shorthand
`/sections` therefore maps to `/farms/{farm_id}/sections`.

| Resource       | Collection                             | Item                                 | Supported writes                      |
| -------------- | -------------------------------------- | ------------------------------------ | ------------------------------------- |
| Farms          | `GET /farms`                           | —                                    | read-only                             |
| Sections       | `GET /farms/{farm_id}/sections`        | `GET /farms/{farm_id}/sections/{id}` | `POST`, `PUT`, tombstone              |
| Plantings      | `GET/POST /farms/{farm_id}/plantings`  | `GET/PUT .../{id}`                   | tombstone                             |
| Observations   | `GET /farms/{farm_id}/observations`    | `GET/PUT .../{id}`                   | existing idempotent create, tombstone |
| Tasks          | `GET/POST /farms/{farm_id}/tasks`      | `GET/PUT .../{id}`                   | tombstone                             |
| Financials     | `GET/POST /farms/{farm_id}/financials` | `GET/PUT .../{id}`                   | tombstone                             |
| Plans          | `GET/POST /farms/{farm_id}/plans`      | `GET/PUT .../{id}`                   | tombstone                             |
| Media metadata | `GET/POST /farms/{farm_id}/media`      | `GET/PUT .../{id}`                   | tombstone                             |

Delete is a `POST` to `.../{id}/delete`. It is a tombstone mutation and
requires both `mutation_id` and the client-observed `expected_version`. The
server keeps the tombstone in the change feed, rejects resurrection, and makes
retries safe.

`GET /farms/{farm_id}/sections/{id}` returns the mobile summary: section,
current planting, current plan, latest health status, observations, tasks, and
financial totals. Boundaries remain optional so mapping can add them later.

## Mutation and synchronization contract

Every create, update, and delete carries a client-generated UUID
`mutation_id`. Creates also carry the client record UUID; updates and deletes
carry `expected_version`.

The server writes the mutation ledger, record change, and sync change in one
transaction:

1. An identical replay returns the existing logical result and creates no
   duplicate record or change-feed item.
2. Reusing a mutation ID with a different payload returns `409
mutation_conflict`.
3. A duplicate record ID or other real database uniqueness failure returns
   `409 record_conflict`/the stable conflict code, never a misleading replay
   error.
4. A stale version returns `409 revision_conflict` and does not modify the
   record.
5. A deleted record returns `409 record_deleted`; it cannot be recreated.

Clients poll the ordered feed:

```http
GET /farms/{farm_id}/changes?since=<cursor>&limit=<n>
```

`since=0` starts at the beginning. Each item has a monotonic cursor, record
type, record ID, operation, version, and timestamp. Resume from `next_cursor`
and apply delete entries even though deleted records are absent from ordinary
active-record lists.

## Acceptance-to-evidence map

| Issue requirement                               | Evidence                                                                                                   |
| ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| New farm has no visible records                 | `test_authenticated_crud_round_trip` and owner-scoped list tests in `test_sync_api.py`                     |
| Planting records are returned in section detail | `test_section_detail_exposes_the_flutter_summary`                                                          |
| Same mutation is idempotent                     | `test_replaying_a_mutation_creates_one_logical_record`, plus update/delete replay tests                    |
| Unknown or malformed input is rejected          | strict DTO and bounded-body tests in `test_sync_api.py`                                                    |
| Foreign farm IDs are hidden                     | `test_writes_to_a_foreign_farm_are_not_found`, `test_records_cannot_be_reached_through_another_owned_farm` |
| Optimistic deletion is safe offline             | stale-delete and deleted-record version tests                                                              |
| Sync has no gaps or duplicates                  | `test_change_polling_resumes_from_a_cursor_without_gaps_or_duplicates`                                     |
| Generated client matches the API                | `make client-check`                                                                                        |
| Raw SQL guardrail remains clean                 | `make check-no-raw-sql`                                                                                    |

The named issue examples use the repository's farm-scoped production routes;
they are not a second unscoped API surface.

## Verification playbook

Run the focused contract suite first:

```sh
uv run pytest apps/backend/tests/test_sync_api.py apps/backend/tests/test_farm_records.py -q
```

Then verify the changed backend scope and generated contract:

```sh
make lint
make typecheck
make check-no-raw-sql
make client-check
```

For the full repository gate, use the parent PR's required checks and run the
integration stack when Docker/PostgreSQL is available:

```sh
make test
make test-integration
```

A local focused pass is evidence for the contract tests only. It is not a
substitute for the parent PR's remote integration, security, migration, and
deployability checks.

## Client retry rules

- Reuse the same mutation UUID and payload after a timeout or lost response.
- Treat `409` as a reconciliation event, not as permission to invent a new
  record ID immediately.
- Refresh the local record when a revision conflict is returned.
- Advance the change cursor only after the page has been applied successfully.
- Never infer ownership from a returned ID; the authenticated farm scope is the
  authority.

This keeps optimistic mobile updates, offline replay, and forward-only sync
consistent across sections and their attached records.
