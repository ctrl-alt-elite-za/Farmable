# Farm records REST and sync API (#11)

This closes the backend half of the offline story: owner-scoped CRUD over the
production farm-record tables plus the synchronization contract #17 consumes.
It adds no new tables - `sync_mutations` and `sync_changes` from #8 remain the
only sync ledger.

## Authentication and scope

Send the access token from `/auth/login` as `Authorization: Bearer <token>`.
The server derives the owner from the verified session and rechecks farm and
section ownership on every query and mutation. A foreign or missing ID returns
404 with the same body either way, so no record can be inferred through IDs,
cursors, media links or error differences. Request bodies are limited to 65,536
bytes on `POST` and `PUT`, reject unknown fields, and bound every string,
number and date.

## Resources

`{resource}` is one of `sections`, `plantings`, `observations`, `tasks`,
`financials`, `plans`, `media`.

| Path                                             | Methods                                              |
| ------------------------------------------------ | ---------------------------------------------------- |
| `/farms`                                         | `GET` owned farms                                    |
| `/farms/{farm_id}/{resource}`                    | `GET` list (optional `section_id`), `POST` create    |
| `/farms/{farm_id}/{resource}/{record_id}`        | `GET` one record, `PUT` update                       |
| `/farms/{farm_id}/{resource}/{record_id}/delete` | `POST` tombstone                                     |
| `/farms/{farm_id}/sections/{record_id}`          | `GET` returns the section detail below               |
| `/farms/{farm_id}/changes`                       | `GET` ordered change feed (`since`, `limit`)         |
| `/farms/{farm_id}/observations`                  | `POST` keeps the #17 create contract with `media_id` |

`sections` has no generic `GET` list item route: `GET /farms/{farm_id}/sections`
lists sections and `GET /farms/{farm_id}/sections/{record_id}` returns the
detail Flutter needs - the section itself, its current planting (crop and
planting date), current saved/approved plan, latest health state, most recent
observations, upcoming tasks, and an income/expense/net summary in cents.

Observations keep their existing create route, which alone accepts a validated
ready `media_id`; `PUT` and `.../delete` are the new edit and tombstone routes.
`media` exposes metadata only: `object_key` is server-owned and can never be set
or read through these routes, and `local_id` is immutable after create.

## Synchronization contract

Every mutation body carries a client-generated `mutation_id`. Create bodies also
carry the client-generated record UUID as `id`; update bodies carry
`expected_version`; delete bodies carry only `mutation_id`.

- Replaying a byte-identical mutation returns the same logical result and writes
  no second record and no second change row.
- Reusing a `mutation_id` for different work returns 409 `mutation_conflict`.
- Creating an ID that already exists returns 409 `record_exists`.
- Updating with a stale `expected_version` returns 409 `revision_conflict`.
- Updating a tombstoned record returns 409 `record_deleted`; a tombstone is
  never resurrected, and the ID cannot be recreated.
- `PUT` replaces every field its DTO declares; fields the DTO does not declare
  are left untouched.

Each accepted mutation appends exactly one `sync_changes` row inside the same
transaction as the record write, so the feed has no gaps. Poll
`GET /farms/{farm_id}/changes?since=<cursor>&limit=<n>` and resume from
`next_cursor`; `since=0` starts at the beginning. Items are ordered by a
monotonic integer `cursor` and expose `record_type`, `record_id`, `operation`
(`create`, `update` or `delete`) and `version`. Deletions stay in the feed as
`delete` entries, so a client that only ever polls forward still learns about
tombstones.

## Verification

```sh
uv run pytest apps/backend/tests/test_sync_api.py apps/backend/tests/test_records_api.py
make lint typecheck check-no-raw-sql
make client-check
```

`make client-check` regenerates `packages/api-client` from the live FastAPI app
and fails on an uncommitted contract diff; run `make client` and commit its
output after changing any route or DTO here.
