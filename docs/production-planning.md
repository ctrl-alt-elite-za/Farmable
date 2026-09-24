# Active-outlook planning and confirmed saves

This is a separate planner from the unchanged sample/demo engine. It uses the
configured active forecast run and stored weather exposure, with no network calls
or silent sample-data fallback. Historical mode refuses synthetic forecasts.
Sample mode remains explicitly labelled and is not production data acceptance.
No live provider, deployment, frontend or issue-completion claim accompanies it.

## Client flow

1. POST `/farms/{farm_id}/planning/preview` with a `PlanRequest`.
   This only reads data: no plan, mutation or proposal row is persisted.
2. Display the candidates, source date, data-kind warning, cash timeline and
   assumptions. Let the farmer choose a candidate and explicitly confirm it.
3. POST `/farms/{farm_id}/planning/confirm` with the exact normalized request from
   the preview, `snapshot_hash`, selected `candidate_id`, `confirmed: true`, a
   client-generated `plan_id` and stable `mutation_id`. `expected_version: 0`
   creates a new plan; an update requires the existing plan's exact version.
4. Read saved plans using the existing `/farms/{farm_id}/plans` routes. Confirmed
   writes publish the existing `plan` create/update sync changes, so consumers
   do not need a second persistence system. A plan is approved, not physically
   planted: confirmation does not create a planting or claim work was performed.

All routes use verified Bearer authentication and enforce farm/section ownership.
Bodies are bounded to 64 KiB, unknown fields are rejected, and responses are
`no-store`. The request supplies a section ID, never its area or an owner ID.
Area comes from the owned section and must be between 1 and 1,000,000 m².

Preview inputs:

- `planting_date`: today through the next 365 days in Africa/Johannesburg, also
  subject to the reviewed payment-calendar coverage below.
- `budget_cents`, required `money_basis_year: 2025`: starting cash in the same
  constant-2025 ZAR basis as the forecast. There is no implicit inflation or
  nominal-cash conversion. The UI must explain this or obtain a reviewed currency
  conversion policy before presenting it as a current-rand budget tool.
- `crops`: 1–8 unique supported crop entries, each optionally specifying
  `minimum_percent` and `promised_kg`. Promised quantity is an estimated harvest
  constraint, not a guarantee of delivery.
- `block_count`: 1–4 equal blocks; `max_results`: 1–5, default 3.
- Required `planting_cost_percent`, `market_commission_bps`,
  `agent_commission_bps`: explicit caller assumptions. One basis point is 0.01%.
  The source has total production costs but does not provide this timing or fees.
- Optional `cash_deadline`: all selected crops must receive payment by this date.
- Optional `goal_margin_cents`: choose the least starting cash needed to meet
  this P50 margin target. Without a goal, rank by highest P50 margin, then lowest
  required cash and a stable candidate hash. Lowering `budget_cents` implements
  Fit my budget; changing inputs always requires another preview/confirmation.

Infeasible requests return `feasible: false`, no candidates and `change_needed`.
When feasible with more cash, the response reports the smallest required budget
for the other unchanged constraints. Impossible goals or conflicting share/
quantity/deadline constraints have explicit reasons; the service never silently
relaxes them. Excessive/invalid inputs return 422; missing, disabled or invalid
active outlooks return `503 outlook_unavailable`.

## Arithmetic and uncertainty

Enumerating crop counts yields at most 495 distinct allocations, including
unplanted blocks. Quantities and costs scale with the section area. Rational
arithmetic retains exact thirds until half-up cent rounding. Displayed quantities
may be recurring decimals; promised-quantity constraints use exact products.

The planting percentage is charged on planting day. Remaining production cost is
split into monthly integer-cent installments through the approximate harvest date,
with remainder cents assigned earliest. Commissions are withheld from P50 sales
on the payment day. Same-day expenses require cash before receipts arrive. The
minimum prefix cash balance determines the required starting cash; final balance
equals starting cash plus estimated margin. No credit or invisible top-up is used.

Harvest adds the source growing-month count, clamping month-end dates. This is
an approximate date, not agronomic proof of harvest timing. Payment is five South
African business days later. The versioned calendar supports 2026–2027 and refuses
unreviewed years, including payments crossing into 2028. The statutory dates and
Sunday/Monday observation rule follow the
[government holiday calendar](https://www.gov.za/zu/about-sa/public-holidays).
It also includes 4 November 2026, declared in Proclamation 346, Gazette 55352,
listed in the [government proclamations](https://www.gov.za/document?field_gcisdoc_doctype=545&field_gcisdoc_subjects=All&search_query=Holidays).
Operators must review new proclamations/years and update the calendar version;
there is no live holiday lookup or assumption that this calendar lasts forever.

Break-even price includes the entered commissions. Three price quantiles do not
define a full probability distribution: the service returns conservative
price-only probability bounds implied by those quantiles, not an interpolated
point probability. These are conditional on the source quantiles being valid,
fixed yield/cost and the entered fees. They are not calibrated farm-profit
probabilities. Weather reasons are included as exposure evidence, never used to
invent yield-loss percentages. Combined crop quantiles are not summed into a
pretend portfolio probability; cross-crop dependence is unknown.

## Confirmation and concurrency

The snapshot hash covers the normalized request, engine/calendar version,
section version/area/boundary and the selected source rows, provenance, weather,
assumptions and calculated results. It is an equality check, not a secret token
or a substitute for authentication. The server recomputes the preview on confirm
and saves its own candidate, never client/model-provided plan amounts.

Farm/section locks serialize with ordinary sync edits. The same forecast-state
lock used by activation/rollback prevents publishing a different run during
confirmation. Existing weather-job locks coordinate with weather publication.
Changed previews return `409 plan_stale`; wrong saved-plan versions return
`409 revision_conflict`. No server refresh is silently accepted on the farmer's
behalf. A missing/deleted source or unsupported date also prevents confirmation.

The plan, approval timestamp, mutation fingerprint and change cursor commit in
one transaction. Exact retries return the accepted receipt without recalculation,
even if forecasting has since been disabled. Reusing a mutation ID with different
content fails. Retries cannot revive deleted plans or claim an old approval is
current after a later edit. Different IDs are different user requests, so clients
must retain IDs across retries. Existing generic manual-plan CRUD is preserved;
its arbitrary JSON is not represented as a server-calculated recommendation.

## Saved-plan history

Migration `0013` adds `plan_revisions`. Each accepted planner confirmation or
ordinary plan create/update/delete appends a snapshot in the same transaction
as the plan and sync change. Exact retries add no revision; rejected or rolled
back writes add none. `(plan_id, version)` is unique. Existing snapshots are
never updated by either write path, and there is no history-edit/restore API.
This is application-level immutability, not protection from a database administrator.

`GET /farms/{farm_id}/planning/plans/{plan_id}/history` returns newest-first
snapshots, with a default of 10 and maximum of 20 per page. Pass the returned
`next_before_version` as `before_version` for the next page. Reads require the
owner's verified session and an active farm; another owner/farm receives 404.
History remains readable for a soft-deleted plan, without reviving it. History
does not need the forecast provider or a still-active source run.

Each row records server-controlled origin: `planner_confirmation`, `manual`,
or `baseline`. User-submitted JSON cannot claim a trusted confirmation origin.
The snapshot preserves the full plan data, status and approval/deletion times;
confirmed plans therefore retain their original source, assumptions and results.

Pre-migration versions cannot be reconstructed. An existing plan's current
version is captured as `baseline` before its next accepted edit; older missing
versions are not fabricated. Until that edit, its history can be empty. There
is no data backfill or rewriting of old migrations.

History is included in the owner's account export and hard-deleted on account
erasure. Deletion takes the farm locks shared by planner/sync writes to fence
late restoration. Chat expiry does not delete saved-plan history. Database
backups and already-downloaded exports remain separate retention responsibilities.
Apply `0013` before deploying this code. Downgrading discards history irreversibly
but leaves current saved plans intact; obtain independent migration review.

## Assistant boundary and remaining acceptance

`preview_planting_plan` is an allowlisted **read-only** tool. It applies the same
planner and conversation farm/consent checks, with a bounded output. No confirm,
approve or save tool exists. A chat message such as “yes” cannot itself write a
plan. The app must render the result safely and send the separate authenticated
confirmation after a user action. Backend code cannot prove a human tapped a
button; frontend confirmation and physical-device acceptance remain required.

Consent notice v3 includes planning inputs/budget and preview results sent to
Gemini. Earlier grants require explicit reconsent. Tool/chat copies obey the
30-day content policy; explicitly saved plans remain separate account records
included in export/deletion. History requires migration `0013`; no dependency is added.

Tests exercise arithmetic, constraints, holidays, source changes, replay and
cross-owner/farm denial; hosted PostgreSQL tests exercise replica races. They use
synthetic inputs and do not establish real-model quality or data calibration.
Full #7 remains open for voice, diagnosis, accounting/evaluation and live/device
acceptance. Full #21 acceptance still needs independent review, including the
history integration and a reviewed nominal-cash conversion policy for a
current-rand UI.
