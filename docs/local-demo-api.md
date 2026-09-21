# Local map-to-plan demo API (provisional)

Related: #8, #11, #12, #22, #25, #26. **MVP slices only; production issues remain
open.** Depends on the planner core in PR39. This separate app is not mounted
into the production API, Flutter application or your colleague's web branch.

## Start

After normal `uv sync --locked`, from the repo root:

```bash
uv run python -m farmable_backend.demo_api.init
uv run uvicorn farmable_backend.demo_api.app:app --host 127.0.0.1 --port 8001
```

Storage initialization is explicit and safe to repeat; server startup does not
run migrations. The default private local file is `.farmable-demo/state.sqlite3`
(gitignored). `FARMABLE_DEMO_DB` can select a dedicated local demo file. This
never reads `DATABASE_URL`, `.env` or provider credentials; SQLite access uses
SQLAlchemy's ORM, not hand-written SQL. Production metadata is unchanged.

Keep **one API worker, bound to loopback**, for this prototype. Do not expose it
as a production service, use real farmer data or point it at an unrelated DB.
Sessions use opaque demo capabilities, not accounts, JWTs or production login.
Tokens have no production expiry/rotation/recovery lifecycle. Only token hashes
are stored. Losing the browser token means losing access to that example farm;
create a new session instead. Local limits: 32 sessions, 20 sections per farm,
40 plan snapshots and 100 successful keyed mutations per farm. Reset reuses a
session and clears its sections/plans/history, not other sessions.

Swagger is at `http://127.0.0.1:8001/docs`; machine-readable provisional shapes
are at `/openapi.json`. Swagger itself loads CDN assets, so it is not an offline
UI. The API and rehearsal need no provider/network connection beyond loopback
after dependencies have been installed.

## Frontend handoff

Create a session with `POST /demo/sessions` and JSON `{}`. The 201 response has
`access_token` and `dashboard` with three example sections (40 m² cabbage,
40 m² spinach, 400 m² available). Store **this prototype token only** locally
if reopening after refresh is desired; do not put it in URLs, logs or Git.
Send `Authorization: Bearer <access_token>` for every subsequent action.

| Action                                   | Endpoint                            | Body / extra header                                              |
| ---------------------------------------- | ----------------------------------- | ---------------------------------------------------------------- |
| Dashboard                                | `GET /demo/farm`                    | None                                                             |
| Open section                             | `GET /demo/sections/{id}`           | None                                                             |
| Create section                           | `POST /demo/sections`               | `{ "name": "North section", "area_m2": "200" }`                  |
| Edit section                             | `PUT /demo/sections/{id}`           | Same shape; `Section-Revision` must match the section's revision |
| Delete section and its plan snapshots    | `DELETE /demo/sections/{id}`        | None                                                             |
| Compare / adjust controls without saving | `POST /demo/sections/{id}/preview`  | Planning controls below                                          |
| Save a proposal                          | `POST /demo/sections/{id}/plans`    | Controls plus optional `selection_index` (default 0)             |
| Replan into a new version                | `POST /demo/plans/{id}/constraints` | Complete new controls, not a partial patch                       |
| Approve                                  | `POST /demo/plans/{id}/approve`     | `{}`                                                             |
| Reopen snapshot                          | `GET /demo/plans/{id}`              | None                                                             |
| Reset this fictional farm                | `POST /demo/reset`                  | `{}`                                                             |

All mutations except session creation and preview require `Idempotency-Key`:
a fresh UUID string per intentional action, **reused on retries of that action**.
Reusing a key with different inputs/route/precondition returns 409. A replay
returns the same resource ID, potentially reflecting later approval/state;
deleted resources cannot be resurrected by replay. Reset starts a new history
generation. Never auto-reset after a save error.

```json
{
  "planting_date": "2026-09-18",
  "budget_cents": 210000,
  "min_crop_shares": [{ "crop": "cabbage", "percent": 50 }]
}
```

Money is integer **ZAR cents**. Areas/quantities serialize as decimal strings.
The available section's best allocation for these controls is two cabbage
blocks, one spinach block and one unplanted block. Preview returns a full
`PlanningResult`; saves return a `SavedPlan`. Display the selected allocation
as `saved.result.plans[saved.selection_index]`. A proposed plan is not approved
and an approved plan is **planned planting**, not physically planted. The
dashboard lists only each section's active approved plan.

Do **not** send `area_m2` or `section_id` in planning controls. The API resolves
both from the token's owned section. Other sessions' section/plan IDs return 404. Editing a section increments its revision, clears its active plan link
and blocks approval of old snapshots; create a new proposal against the edited
section. Approval never trusts numbers submitted by the frontend.

### Boundaries

Instead of `area_m2`, section create/edit can accept `boundary` as a GeoJSON
Polygon with **one closed outer ring**, 3–32 distinct corners, coordinates in
`[longitude, latitude]` order. No holes, dateline crossings, polar fields,
self-crossings or self-touching rings. Small local extents only (≤ 0.1° span,
1–1,000,000 m²). Area uses a local approximate projection and is rounded to
0.01 m², not survey accuracy. Moving corners changes the computed area.
Supplying both a boundary and area is rejected. Without a boundary, area is
clearly `farmer_supplied`; soil stays unknown either way.

### Failure and sample-data states

The persistent sample-data label and assumptions must appear in the UI.
Yields/prices/costs/growth windows are **invented arithmetic fixtures**; there
is no live weather or soil suitability assessment. Only September 2026 dates
are supported. Health and analytics are null, not invented percentages.

A well-formed infeasible/unsupported preview is 200 with `feasible: false`,
`reason` and no plans. Attempting to save it is 422 and writes nothing. Malformed
input is 422; stale state/conflicting keys are 409; failed storage is 500—not
success. All errors use `{ "error": { "code": "...", "message": "..." } }` and
request IDs. Maximum request body is 64 KiB; the existing IP rate limiter applies.
Debounce preview calls rather than sending one request per keystroke.

CORS defaults to `http://localhost:5173` and `http://127.0.0.1:5173`. Set
`FARMABLE_DEMO_ORIGINS` to explicit comma-separated origins if needed; no
wildcards. Browser session responses are not cacheable. CORS is not production
authentication or permission to publish this local app.

## Rehearse

```bash
uv run python -m farmable_backend.demo_api.rehearse
uv run pytest apps/backend/tests/test_demo_api.py -q
```

The rehearsal owns a temporary local store/helper server, performs three real
HTTP journeys and closes its server and temporary data before reporting success. It checks normal
planning → half cabbage → tighter budget → approval → dashboard → reopen,
plus impossible budget and unsupported date. It prints no tokens.

**This is backend evidence only**, not a browser rehearsal, timing claim, backup
video or `make demo-ready`. Frontend wiring, three actual browser runs, reset
UX and a private backup still need doing. Full tables/contracts, account auth,
animal sections, production deletion jobs, dashboard widgets/cache, live
outlooks, advanced cash flow/goals, voice/interrupt cancellation and native
#26 acceptance remain unfinished. The full issues must stay open.
