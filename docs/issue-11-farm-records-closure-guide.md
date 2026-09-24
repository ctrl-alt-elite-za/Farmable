# Issue #11 farm-records REST and sync contract guide

This guide documents the delivered farm-records and synchronization behavior
for issue #11: the generic contract inherited from the PR #72 stack, plus this
PR's own application changes closing the remaining acceptance gaps (crop
catalogue validation, crop-calendar harvest windows, animal sections, planting
date bounds, and cascading section deletion). It records how to verify all of
it without replaying the implementation commits.

## Stack relationship

PR #72 is the parent stack. The generic farm-record implementation was merged
earlier by PR #59 and is an ancestor of PR #72's head. This PR adds the
remaining issue #11 application behavior (crop catalogue, harvest windows,
animal sections, planting date bounds, cascading section delete) on top of
that generic contract, plus this guide; it does not copy the generic records
routes or repositories again.

Useful checks when reviewing the stack:

```sh
git merge-base origin/resolve-issue/9-complete-backend-identity HEAD
git diff --stat origin/resolve-issue/9-complete-backend-identity...HEAD
```

The first command prints the common ancestor: the parent branch can advance,
so its latest tip need not be an ancestor of HEAD. The second shows this PR's
application changes and related documentation. Check the parent's current
review and CI separately; the guide is not evidence that later parent fixes
are already included in this branch.

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
requires both `mutation_id` and the client-observed `expected_version`. A
section delete also carries `expected_child_versions`, mapping every attached
record ID to the version the client observed, so a concurrent child edit is
reported as a conflict instead of being silently erased. The
server keeps the tombstone in the change feed, rejects resurrection, and makes
retries safe.

`GET /farms/{farm_id}/sections/{id}` returns the mobile summary: section,
current planting, current plan, latest health status, observations, tasks, and
financial totals. Boundaries remain optional so mapping can add them later.

Sections carry `kind` (`crop` or `animal`, default `crop`); pens share the
same routes, mapping, and carousel as crop sections rather than a second
system. Plantings carry an optional `crop_type_code`; when set it must name a
row in the `crop_types` catalogue (otherwise `422 unknown_crop_type`) and the
server computes `harvest_from`/`harvest_to` from `crop_calendars` and
`planted_on`. Existing clients that only send free-text `crop` are unaffected.
An exact catalogue crop name cannot be paired with a different code
(`422 crop_type_conflict`); custom free-text labels remain supported. Changing
the crop to an unknown free-text value without a code clears the previous
catalogue binding and harvest window. Date-only edits keep an unchanged custom
label's existing binding. Missing validated calendars produce null harvest dates.
`planted_on` is rejected with `422 planted_on_out_of_range` outside two years
of today in either direction. `kind` and the crop/harvest fields live in
companion tables (`section_kinds`, `planting_crops`) keyed to the section/
planting id, not new columns on `sections`/`plantings`: migration `0003` is
pinned to those tables' original columns by `test_farm_schema.py`, so new
attributes follow migration `0011`'s `farm_locations` pattern instead.

Deleting a section cascades: every planting, observation, task, financial
record, plan, and media row attached to it is tombstoned in the same
transaction as the section, and each cascaded tombstone publishes its own
`SyncChange` row under the section's own `mutation_id` so other devices learn
of the cascade, not only the section's own deletion. Deleting an
already-deleted section (a new mutation, not a replay) is a no-op that leaves
the cascaded records untouched and publishes no further cascade.

Photo uploads become unavailable immediately, but storage removal is asynchronous.
Deletion requeues every attempt, including previously cleaned attempts. The
janitor waits at least its existing one-hour safety window from deletion and
respects actual signed-form and worker-lease expiry before its final cleanup.
An already-issued form cannot be revoked by changing a database timestamp;
late uploads and publications must remain covered by the durable cleanup intent.

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

## Delivered scope

This PR implements the issue #11 runtime behavior: the generic
owner/farm-scoped records, strict DTOs, optimistic versions, mutation replay,
tombstones, and change-feed behavior described above, plus the crop
catalogue/harvest-window, animal-section, planting-date-bound, and
cascading-delete behavior described in this guide. Individual animals (#13),
mapping (#15), the dashboard (#12), and a custom crop catalogue remain out of
scope. Legacy free-text crop labels are retained for compatibility; they do
not establish a validated catalogue identity or a harvest estimate.

The crop catalogue (`crop_types`/`crop_calendars`, migration `0025`) seeds crop
identities (cabbage, spinach, tomato, potato, onion and carrot), **not harvest
durations**. Invented calendars are deliberately excluded from production.
Until validated calendars are supplied, harvest dates remain null. Tests
cover calculation from an explicitly supplied calendar and the unavailable
case; they do not validate agronomic data. Load future validated data through
an additive migration or an approved import, never by rewriting an applied
migration. Do not treat this guide or passing code tests as evidence that
production harvest estimates are already populated.

## Acceptance-to-evidence map

| Issue requirement                                   | Evidence                                                                                                         |
| --------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------- |
| New farm has no visible sections                    | `test_new_account_has_no_sections`                                                                               |
| Planting harvest window from crop_calendar          | `test_crop_harvest_window_from_calendar`                                                                         |
| Unknown crop_type_code is rejected                  | `test_unknown_crop_rejected`                                                                                     |
| Planting date bounded to two years of today         | `test_planted_on_out_of_range_rejected`                                                                          |
| Animal sections (`kind=animal`) are accepted        | `test_section_kind_defaults_to_crop_and_accepts_animal`                                                          |
| Deleting a section cascades to its attached records | `test_delete_section_cascades` (idempotent: repeats the delete under a second mutation)                          |
| Same mutation is idempotent                         | `test_replaying_a_mutation_creates_one_logical_record`, plus update/delete replay tests                          |
| Unknown or malformed input is rejected              | strict DTO and bounded-body tests in `test_sync_api.py`                                                          |
| Foreign farm IDs are hidden                         | `test_writes_to_a_foreign_farm_are_not_found`, `test_records_cannot_be_reached_through_another_owned_farm`       |
| Optimistic deletion is safe offline                 | stale-delete and deleted-record version tests                                                                    |
| Sync has no gaps or duplicates                      | `test_change_polling_resumes_from_a_cursor_without_gaps_or_duplicates`                                           |
| Migration is additive and matches the ORM           | `test_crop_catalogue_migration_is_additive_and_matches_models`, `test_farm_schema.py`, `test_photo_migration.py` |
| Generated client matches the API                    | `make client-check`                                                                                              |
| Raw SQL guardrail remains clean                     | `make check-no-raw-sql`                                                                                          |

The named issue examples use the repository's farm-scoped production routes;
they are not a second unscoped API surface.

## Verification playbook

Run the focused contract suite first:

```sh
uv run pytest apps/backend/tests/test_sync_api.py apps/backend/tests/test_farm_records.py apps/backend/tests/test_crop_catalogue_migration.py apps/backend/tests/test_farm_schema.py -q
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
