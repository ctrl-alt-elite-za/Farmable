# Issue #11 farm-records REST and sync contract guide

This guide documents the delivered generic farm-records and synchronization
behavior for issue #11. The implementation is already present in the PR #72
stack through the merged farm-records work. This document makes that subset
explicit and records how to verify it without replaying the implementation
commits. It is not, by itself, evidence that every issue-level acceptance
criterion is complete.

## Stack relationship

PR #72 is the parent stack. The farm-record implementation was merged earlier
by PR #59 and is an ancestor of PR #72's head. This documentation PR therefore
contains only the contract guide; it must not copy the records routes,
repositories, or generated client files again.

Useful checks when reviewing the stack:

```sh
git merge-base origin/resolve-issue/9-complete-backend-identity HEAD
git diff --stat origin/resolve-issue/9-complete-backend-identity...HEAD
```

The first command prints the common ancestor: the parent branch can advance
after this documentation branch is created, so its latest tip need not be an
ancestor of HEAD. The second should show only the contract artifact (and any
deliberately related documentation change). Check the parent's current review
and CI separately; this documentation diff does not prove the latest parent
fixes are already included in this branch.

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
type, record ID, operation, version, and timestamp. Keep a durable polling
watermark equal to the last item successfully applied. `next_cursor` is only a
page-continuation hint: it is null on the terminal page, even when that page
contains items. A terminal page must therefore advance the watermark from its
last item, not reset it to zero or send null as the next request.

For example, if a poll with `since=0&limit=2` returns cursors `1` and `2` with
`next_cursor=null`, apply both entries and persist watermark `2`. A later poll
uses `since=2`; it will return a newly-created cursor `3` when one exists.
Apply delete entries even though deleted records are absent from ordinary
active-record lists.

## Delivered subset and outstanding issue requirements

The current stack provides the generic owner/farm-scoped records, strict DTOs,
optimistic versions, mutation replay, tombstones, and change-feed behavior
described above. The following issue-level requirements are not established by
this guide or by the generic contract tests and remain outstanding before
claiming issue #11 complete:

- crop choices must be restricted to the `crop_types` catalogue;
- planting dates must produce the required `crop_calendar` harvest window;
- animal sections (`kind=animal`) must be accepted where required; and
- deleting a section must cascade cleanup/tombstones to its attached records
  and stored media.

These gaps should be implemented and covered by dedicated acceptance tests in
the appropriate application PR. This PR documents the existing subset only.

## Acceptance-to-evidence map

| Issue requirement                                               | Evidence                                                                                                   |
| --------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------- |
| New farm has no visible records                                 | `test_authenticated_crud_round_trip` and owner-scoped list tests in `test_sync_api.py`                     |
| Planting records are returned in section detail                 | `test_section_detail_exposes_the_flutter_summary`                                                          |
| Same mutation is idempotent                                     | `test_replaying_a_mutation_creates_one_logical_record`, plus update/delete replay tests                    |
| Unknown or malformed input is rejected                          | strict DTO and bounded-body tests in `test_sync_api.py`                                                    |
| Foreign farm IDs are hidden                                     | `test_writes_to_a_foreign_farm_are_not_found`, `test_records_cannot_be_reached_through_another_owned_farm` |
| Optimistic deletion is safe offline                             | stale-delete and deleted-record version tests                                                              |
| Sync has no gaps or duplicates                                  | `test_change_polling_resumes_from_a_cursor_without_gaps_or_duplicates`                                     |
| Crop catalogue/calendar, animal sections, and cascading cleanup | Outstanding; generic contract tests do not establish these issue-specific requirements.                    |
| Generated client matches the API                                | `make client-check`                                                                                        |
| Raw SQL guardrail remains clean                                 | `make check-no-raw-sql`                                                                                    |

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
- Advance the durable change watermark to the last applied item's cursor only
  after a nonempty page has been applied successfully. Keep the previous
  watermark when the page is empty; do not use a null `next_cursor` as a
  watermark.
- Never infer ownership from a returned ID; the authenticated farm scope is the
  authority.

This keeps optimistic mobile updates, offline replay, and forward-only sync
consistent across sections and their attached records.
