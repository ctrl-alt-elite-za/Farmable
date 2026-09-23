# Assistant backend: implementation and acceptance status

Issue #7 remains open. This implements durable authenticated text conversations,
bounded provider orchestration and read-only farm tools. It does **not** complete
the promised voice-to-approved-plan journey. Do not enable live operation merely
because the synthetic tests pass.

The selected voice path remains Gemini Live. Its new
[conversation-scoped backend contract](assistant-live.md) adds explicit audio
consent, locked read tools and durable session interruption without modifying the
Flutter UI. It does not implement microphone/playback or prove Zulu quality.

## Issue #7 acceptance map

This PR does not reduce issue #7's production requirements. The provider foundation
was already present in its base commit; it is not new work delivered by PR #71.
The following distinguishes implementation from acceptance evidence, addressing
the scope review on PR #71.

| Requirement                                                           | Evidence in this repository                                                                                                                     | Remaining acceptance                                                                                                                                                 |
| --------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Per-service adapters, retries and circuit breakers                    | `integrations/registry.py`, individual service modules and `base.py`; `test_integrations.py` checks retry and circuit behavior                  | Real-provider verification; Azure REST request bounds are not the required SDK silence behavior                                                                      |
| Success/error/slow fakes and staging-only fault flags                 | `integrations/fakes.py`, `settings.py`; parametrized fake, timeout and fault tests in `test_integrations.py`                                    | Recorded real-response comparison and consumer-level degradation checks; current fixtures are synthetic                                                              |
| Smoke command, crop coverage, credentials/cost/fallback documentation | `integrations/smoke.py`, `make smoke`, `docs/services.md`, `docs/provider-verification.md`                                                      | Authorized real staging runs, account/security settings and crop-coverage evidence; a command existing is not a PASS                                                 |
| Twilio confined to integrations                                       | `integrations/twilio.py`; static source regression in `test_integrations.py` checks SDK imports and literal provider hosts outside the boundary | Continue enforcing this boundary; the check is not a sandbox against dynamically constructed imports/URLs                                                            |
| Authenticated assistant and interrupted text history                  | PR #71 runtime, read-only planning previews, explicit confirmation API and stale-plan checks                                                    | Frontend confirmation journey, production input acceptance and real-model grounded action verification                                                               |
| Voice and crop diagnosis                                              | Gemini Live handoff plus conversation-scoped voice consent, read tools and durable session interruption                                          | Selected Gemini device-audio/language acceptance and playback interruption, queued farm-scoped diagnosis; Azure-specific criteria are not claimed as implemented      |
| Accounting, evaluation and privacy                                    | Bounded admission reservations, synthetic regressions, owner export/deletion, conversation consent/revocation and 30-day chat-content expiry    | Actual priced settlement, system-spend acceptance, calibrated/adversarial evaluations, provider/backup retention review, consent UI and appropriate provider caching |
| Deployment and full journey                                           | Existing CI checks; no live activation in this PR                                                                                               | Approved configuration, real-provider contracts, physical-device and deployed end-to-end evidence                                                                    |

Keep #7 open and this PR explicitly partial. Do not substitute the synthetic
evaluation command, the demo planner or a green CI run for these missing criteria.

## Implemented contract

All routes use the existing phone- and email-verified Farmable Bearer session.
No caller or model can supply an owner ID. Conversations are bound to one farm;
tools cannot access another farm, including another farm owned by the same user.
Responses are `no-store`. Render assistant text as plain text, not trusted HTML,
Markdown actions or commands.

Before submitting a turn, GET `/assistant/conversations/{id}/consent` and display
the returned notice and exact model. An explicit user action may PUT the returned
`notice_version` and `model` to that same path. Do not grant permission on page
load, infer it from chat text or expose granting as a model tool. A new conversation
has no permission, even in fake mode; existing conversations are not backfilled.
Missing permission returns 403 before spending a reservation or calling Gemini.
Changing the model or notice invalidates old permission.

DELETE that path withdraws permission and durably interrupts every running turn
in the conversation. It is idempotent, farm/owner-scoped and works even when
generation is disabled. Regranting does not revive interrupted turns. The runtime
checks before each provider round and tools recheck permission; the cross-replica
watcher closes an already-running stream after it observes withdrawal. Requests
already sent to the provider cannot be recalled, and provider-side deletion is
not implied. GET history remains available to its owner after withdrawal.

| Method/path                                                 | Request                                            | Response                                                |
| ----------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------- |
| `POST /assistant/conversations`                             | `id` (client UUID), `farm_id`                      | Conversation; same ID/farm is idempotent                |
| `POST /assistant/conversations/{id}/turns`                  | `id` (client UUID), `message` (1–4,000 characters) | SSE stream                                              |
| `GET /assistant/conversations/{id}/turns`                   | Optional `before` turn UUID                        | Latest 20 turns, newest first; `next_before` cursor     |
| `GET /assistant/conversations/{id}/turns/{turn}`            | None                                               | Durable turn snapshot                                   |
| `POST /assistant/conversations/{id}/turns/{turn}/interrupt` | None                                               | Idempotent terminal transition; no new provider request |

POST bodies are bounded to 64 KiB before JSON buffering. Unknown request fields
are rejected. Missing/revoked sessions receive 401; another owner's conversation
or turn receives 404. A repeated turn UUID with a changed message returns 409
while its content remains; an expired UUID returns only its erased snapshot.
An admitted turn UUID is never generated again, including after failure or a lost
response. Retry it to retrieve a snapshot; use a **new** UUID only when the farmer
explicitly requests a new generation. A running replay finishes with
`error/turn_in_progress`; poll the authenticated GET route, not a paid retry loop.

Each SSE event is `event: <type>` and one JSON `data:` line:

```json
{
  "type": "text",
  "turn_id": "00000000-0000-0000-0000-000000000001",
  "data": { "text": "A reply fragment" }
}
```

The stream starts with `accepted`, may emit `text` and `tool`, and terminates with
`done`, `error` or `interrupted`. An error after HTTP headers uses the terminal
event, not an HTTP status change. Disconnects cannot receive a terminal event:
the durable snapshot is authoritative. Partial replies are saved before delivery.
Interrupted replies remain labelled in subsequent conversation context. Raw
provider errors and hidden thoughts/signatures never enter public events or
conversation history. Opaque signatures stay only in memory for the current tool
loop, following Google's [function-calling protocol](https://ai.google.dev/gemini-api/docs/generate-content/function-calling).

## Tools and grounding

`list_sections`, `get_crop_outlook` and `preview_planting_plan` are available. Tool names are explicitly
allowlisted, arguments are validated, and ownership is checked again at execution.
No arbitrary code, URLs, database query, model-supplied identity or mutation is
executed. Tool outputs are saved and returned with the turn. Crop outlooks retain
their source run, as-of date, 2025-rand basis, assumptions, weather availability
and synthetic-data warning. A missing outlook is an explicit tool error.

This is **tool-result grounding**, not proof that every generated sentence is
correct. The prompt requires fresh evidence and forbids fabricated actions, but a
prompt is not a security boundary or a calibrated factuality evaluator. Real-model
grounding and adversarial evaluations remain a release gate. Planning previews
must not be presented as saved plans. The model cannot confirm writes or diagnose photos.

The original demo engine is unchanged. The separate active-outlook planner now
compares crops and allocates blocks with budget, deadline, minimum-share and
promised-quantity constraints. It provides a cash timeline and goal mode using
explicit cost-timing/fee assumptions. A separate authenticated confirmation API
rechecks the snapshot and saved-plan version, then atomically saves through the
existing sync ledger. It is never exposed as a model tool. See
[production-planning.md](production-planning.md) for the full contract, monetary
basis, calendar bounds, uncertainty and remaining production acceptance.

## Bounded execution and cancellation

- Four active streams per process; one active turn per owner across replicas.
- Three admissions per rolling minute and, by default, 20 per rolling 24 hours.
- At most four provider calls and four tool executions per turn; no automatic
  generation retries. Last round forbids more tools.
- A 60-second overall generation deadline, 10 seconds to the first text/tool
  response of each call, 1,024 maximum output tokens per call, 256 provider events
  and 16,000 visible characters per turn. The existing adapter also bounds its
  wire response. Sending to a stalled client is limited to five seconds.
- A one-event producer queue; one task owns the provider stream throughout,
  including circuit half-open probe cleanup. Cancellation closes that stream.
- Database cancellation polling every 200 ms makes cross-replica interruption
  observable. That interval is **not** evidence of the end-to-end 300 ms voice
  target: device playback and deployment latency still need measurement.
- Crashed/orphaned turns expire after 90 seconds when read or on new admission.
  Expiry never reruns a provider call or refunds an ambiguous reservation.

Database transactions are short; network I/O never runs under their locks.
Migration-seeded global admission locking avoids first-write races. Conversation
and farm locks fence late output after cancellation/deletion. History has bounded
pages, and provider context uses at most six prior completed/interrupted exchanges
and 16 KiB of history, within a 64 KiB total request bound. This is bounded local
context reuse, **not** provider-side context caching.

## Operator policy and accounting

Apply migration `0010` before using the feature. It creates three additive tables
and the budget-lock singleton; startup never runs migrations. Downgrade is lossy:
disable the feature and drain requests first; it removes history and reservations.

Migration `0011` adds conversation-scoped consent receipts without granting
permission to any existing user. Receipts join account exports and cascade on
account deletion. Disable and drain generation before downgrade; removing these
receipts is lossy. No deployment or migration has been run against live data.

Migration `0012` adds a nullable content-erasure timestamp and cleanup index.
Apply through `0012` before deploying either the API or worker, including when
generation is disabled. Existing history uses its original message timestamp;
there is no fresh 30-day grace period. Downgrading cannot restore erased content.
The index build and table alteration require migration review; the connection
timeouts also apply to these operations. Drain workers before downgrading.

The migration scanner cannot see the connection-level timeouts already applied by
`make_engine(migration=True)` (1-second lock timeout, 5-second statement timeout).
Its missing-`SET` warnings still require maintainer review and the
`migration-approved` label; this PR does not suppress them or approve itself.

Generation defaults to disabled. Operators must supply all of:

| Setting                            | Meaning                                                                     |
| ---------------------------------- | --------------------------------------------------------------------------- |
| `ASSISTANT_ENABLED`                | Explicit enablement, default false                                          |
| `ASSISTANT_POLICY_MODEL`           | Exact configured Gemini model; `fixture-model` only for isolated fake tests |
| `ASSISTANT_POLICY_DATE`            | ISO date of reviewed pricing/reservation policy; expires after 30 days      |
| `ASSISTANT_TURN_RESERVE_MICRO_USD` | Positive conservative reservation for the **entire** bounded turn           |
| `ASSISTANT_DAILY_BUDGET_MICRO_USD` | Maximum global reservation total per UTC day                                |
| `ASSISTANT_DAILY_TURNS_PER_USER`   | Rolling 24-hour admission limit, default 20, maximum 100                    |

Existing integration-mode/key/model configuration still applies. No deployment
variables, Secret Manager values or provider billing settings are changed by this
PR. Fake mode is still restricted to CI/staging.

Reserve against the **worst case for the selected model**: all four calls, their
input/context, output/thinking tokens and applicable provider charges. Reservations
are atomic and retained even on timeout/cancellation. Policy fingerprints must
match across replicas for the UTC day; a differing policy fails closed rather than
silently raising the cap mid-day. Changing policy requires an operator-controlled
rollout/day transition, never deleting reservation rows to force admission.

The recorded reservation is **not actual billed cost**. Sanitized token usage is
recorded per completed provider exchange when supplied; missing usage stays
unknown, not zero cost. Model-priced settlement and reconciliation are unfinished.
A too-small operator reservation can understate actual spend: this gate cannot
guarantee the provider invoice ceiling. Provider quotas and a validated pricing
policy are still required; budget alerts alone are not a hard stop. Do not label
this as completion of #7's production spend-accounting requirement.

## Privacy and release gates

Account exports include this owner's conversation/turn records. Deleting the
identity cascades conversation content; the global anonymous reservation total
remains so account recreation cannot refund the system budget. No audio is
captured here. Provider-side retention is governed separately by the chosen
provider/account terms; a local deletion does not prove upstream deletion.

Before live enablement, connect the frontend's explicit consent interaction and
review provider/backup retention with #9, verify account configuration and model support, review
the spending policy, and obtain explicit approval for billable acceptance calls.
There have been **no live calls** during this implementation.

### Thirty-day chat retention

Each user message and its associated reply/tool results expire 30 × 24 hours
after the server accepted that message (`created_at`). Reading, reopening,
regranting permission or sending a new message never extends older turns.
History, account exports and new model context exclude expired turns even if
cleanup is delayed. Individual GET/retry requests return an empty snapshot with
`content_deleted_at`; an expired ID never triggers another paid generation.

The existing background-worker process erases `message`, `reply` and `tools` in
batches of 100 using row locks and `SKIP LOCKED`. It checks every 60 seconds when
idle and every second while a batch is full, including with integrations disabled.
API reads/updates of individual expired turns also erase their content. Late
callbacks cannot restore it. Keep the worker running: a stopped/unhealthy worker
delays physical cleanup, although API access still expires. Monitor worker health
and the fixed `Assistant retention cleanup unavailable` error; investigate rather
than treating worker uptime alone as proof that cleanup succeeded.

Content-free turn IDs, ownership links, timestamps, status, model/policy and
numeric usage/reservations remain for retry safety and accounting until account
deletion. Conversation containers and consent receipts also remain. This is chat
**content** retention, not deletion of every account record. Approved planting
plans are independent records and are not modified by chat cleanup.

Notice `gemini-conversation-v3` describes this policy and planning data sent to Gemini. Existing v1/v2 grants are
invalid for new generation and require explicit consent again; no grants are
silently upgraded. Frontend consent controls remain a separate integration task.

This implementation does not erase provider copies, snapshots, backups or
previously downloaded exports. Operators must separately establish backup expiry
and restore procedures: after restoring a database, migrate it and complete the
cleanup before allowing direct access to restored content. Review the chosen
Google account's retention terms before making any upstream deletion promise.

Still required for full #7: frontend confirmation and real-data planning acceptance;
production speech/language handling and TTS cancellation; queued crop
diagnosis; provider context caching where appropriate; actual priced usage and
system spending acceptance; calibrated/model-quality evaluations; real-response
contracts and all provider/manual checks in [services.md](services.md).
Flutter integration/device acceptance remains with #23–#25/#4, deployment with
#6 and integrated rehearsal with #26. These are outstanding requirements, not
waived scope.

## Verification

`make eval-assistant SET=dev` runs deterministic protocol/security regression
checks, explicitly labelled as synthetic—not a calibrated model judge report.
`make assistant-evals` is the CI runner's alias for the same command.
`make test` includes these tests and migration-shape checks.
`make test-integration` explicitly runs the PostgreSQL admission/budget races
against the disposable migrated stack. Ordinary SQLite tests do not establish
cross-replica row-lock correctness. Required CI retains all existing checks.
