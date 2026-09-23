# Assistant backend: implementation and acceptance status

Issue #7 remains open. This implements durable authenticated text conversations,
bounded provider orchestration and read-only farm tools. It does **not** complete
the promised voice-to-approved-plan journey. Do not enable live operation merely
because the synthetic tests pass.

## Implemented contract

All routes use the existing phone- and email-verified Farmable Bearer session.
No caller or model can supply an owner ID. Conversations are bound to one farm;
tools cannot access another farm, including another farm owned by the same user.
Responses are `no-store`. Render assistant text as plain text, not trusted HTML,
Markdown actions or commands.

| Method/path                                                 | Request                                            | Response                                                |
| ----------------------------------------------------------- | -------------------------------------------------- | ------------------------------------------------------- |
| `POST /assistant/conversations`                             | `id` (client UUID), `farm_id`                      | Conversation; same ID/farm is idempotent                |
| `POST /assistant/conversations/{id}/turns`                  | `id` (client UUID), `message` (1–4,000 characters) | SSE stream                                              |
| `GET /assistant/conversations/{id}/turns`                   | Optional `before` turn UUID                        | Latest 20 turns, newest first; `next_before` cursor     |
| `GET /assistant/conversations/{id}/turns/{turn}`            | None                                               | Durable turn snapshot                                   |
| `POST /assistant/conversations/{id}/turns/{turn}/interrupt` | None                                               | Idempotent terminal transition; no new provider request |

POST bodies are bounded to 64 KiB before JSON buffering. Unknown request fields
are rejected. Missing/revoked sessions receive 401; another owner's conversation
or turn receives 404. A repeated turn UUID with a changed message returns 409.
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

Only `list_sections` and `get_crop_outlook` exist. Tool names are explicitly
allowlisted, arguments are validated, and ownership is checked again at execution.
No arbitrary code, URLs, database query, model-supplied identity or mutation is
executed. Tool outputs are saved and returned with the turn. Crop outlooks retain
their source run, as-of date, 2025-rand basis, assumptions, weather availability
and synthetic-data warning. A missing outlook is an explicit tool error.

This is **tool-result grounding**, not proof that every generated sentence is
correct. The prompt requires fresh evidence and forbids fabricated actions, but a
prompt is not a security boundary or a calibrated factuality evaluator. Real-model
grounding and adversarial evaluations remain a release gate. Unsupported saving,
allocation and diagnosis requests must not be presented as completed actions.

The merged numerical allocation engine is explicitly a demo engine with sample
inputs; the production API exposes outlooks but does not yet expose the full
budget/deadline/minimum-share planner contract. This implementation does not
quietly repurpose that demo engine or invent a production plan. Completing that
integration and explicit-confirmation mutations is still required by #7/#21.

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

Before live enablement, complete the external-processing consent integration and
retention policy with #9, verify account configuration and model support, review
the spending policy, and obtain explicit approval for billable acceptance calls.
There have been **no live calls** during this implementation.

Still required for full #7: confirmed production planning actions and stale-plan
protection; production speech/language handling and TTS cancellation; queued crop
diagnosis; provider context caching where appropriate; actual priced usage and
system spending acceptance; calibrated/model-quality evaluations; real-response
contracts and all provider/manual checks in [services.md](services.md).
Flutter integration/device acceptance remains with #23–#25/#4, deployment with
#6 and integrated rehearsal with #26. These are outstanding requirements, not
waived scope.

## Verification

`make eval-assistant SET=dev` runs deterministic protocol/security regression
checks, explicitly labelled as synthetic—not a calibrated model judge report.
`make test` includes these tests and migration-shape checks.
`make test-integration` explicitly runs the PostgreSQL admission/budget races
against the disposable migrated stack. Ordinary SQLite tests do not establish
cross-replica row-lock correctness. Required CI retains all existing checks.
