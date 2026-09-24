# Assistant usage accounting and billing comparison

The backend now records each text-model exchange durably **before** contacting
Gemini. This is separate from the existing admission reservation. No UI, Gemini
Live transport, provider credentials or cloud billing configuration is changed.

## Receipts and pricing

Migration `0016` adds `assistant_model_calls` and `assistant_turn_costs`; migrate before deploying this API
revision, including when generation is disabled (account export uses the table).
It is additive, needs independent review, and does not invent historical usage.
Disable/drain generation before downgrade: removing the table loses receipts,
not provider charges. Do not reuse revision numbers across other PRs.

One `(turn_id, round_index)` can start only once, including across API replicas.
Receipts have numeric usage, configured/reported model, a pricing snapshot,
billing-project scope and timestamps, never prompts, replies, images or credentials.
States are `started`, `unknown`, `unpriced` and `priced`. A crashed worker leaves
`started`, which reports as unknown cost, not zero. Interruption/error callbacks
can save partial numeric counts without restoring chat output. Finalization is
idempotent. A separate settlement transaction reconciles terminal turns against
the admission counter; the billing-file comparator never changes that counter.

Set `ASSISTANT_BILLING_PROJECT` to the **Farmable** project ID and
`ASSISTANT_TEXT_PRICING` to a reviewed JSON rate card. Leaving them unset is safe:
generation retains its existing reservation policy, while receipts remain explicitly
unscoped/unpriced. A rate card has this shape (the example rates/model are synthetic,
not a recommendation or an approved production price):

```json
{
  "model": "example-pinned-model",
  "response_models": ["example-reported-version"],
  "valid_from": "2026-09-24",
  "valid_until": "2026-09-30",
  "input_micro_usd_per_million": 1000000,
  "cached_input_micro_usd_per_million": 100000,
  "output_micro_usd_per_million": 2000000,
  "max_prompt_tokens": 1000
}
```

Rates are integer millionths of a US dollar **per million tokens**. Use the selected
model's actual tier, billing mode and reported version; cards cover at most 31
calendar days. Do not reuse a text card for Live audio, images, paid grounding,
batch/flex rates. Explicit cache creation/storage needs the additional reviewed
rates described below; there are no assumed provider prices.
`max_prompt_tokens` prevents applying a lower-context tier above its reviewed limit.
These settings join the existing policy fingerprint: coordinate replica rollouts
and the UTC-day policy boundary rather than clearing the budget row.

The calculation subtracts cached input from ordinary input and adds thinking to
output, then rounds upward once to a micro-dollar. It requires consistent total
usage, a matching reported model and an in-date card. Missing/inconsistent usage
or an unsupported tier leaves cost null. These are **model-priced estimates based
on reported usage**, not provider invoice charges. The contract follows Google's
[usage metadata](https://ai.google.dev/api/generate-content#v1beta.GenerateContentResponse.UsageMetadata)
and [model-specific pricing](https://ai.google.dev/gemini-api/docs/pricing).

Owner exports include linked receipts, including numeric receipts for expired
chat content. Account deletion removes the turn link (`ON DELETE SET NULL`) but
retains content-free cost records for system accounting; no owner/farm ID is stored
in this table. A late callback cannot recreate that link or the erased conversation.
Review this retention separately from the 30-day chat policy and backup retention.

## Settlement and recovery

Admission atomically creates a content-free turn-cost record alongside the turn
and reservation. The API settles on completion/cancellation; the existing worker
also reconciles due records in batches of 100 (60 seconds idle, one second while
full). Keep `ASSISTANT_ENABLED=true` **on the worker** until outstanding costs
have drained, even if API generation is disabled. This worker makes no provider
calls. Monitor `Assistant accounting reconciliation unavailable` and unsettled/
overrun records; worker uptime alone is not proof of successful settlement.

The shared `assistant_budget.reserved_micro_usd` counter now means **held
reservations plus settled estimates** for its UTC admission day. Under the same
global-first row lock as admission, a terminal turn with fully priced exchanges
replaces its reservation with their total exactly once. Overruns stay in the
counter, record `reservation_exceeded`, and constrain further admissions against
the unchanged cap. A provably never-started exchange costs zero; crashed/partial/
unpriced exchanges keep their reservation, not a fabricated zero.

The worker expires abandoned running turns only after their durable deadline.
It does not replay provider requests. A prior-day settlement never refunds
today's counter. Charges are attributed to the turn's admission day, even across
midnight; provider usage windows can differ. Account deletion removes identity
links, not receipts or settlement keys. Multiple replicas/restarts cannot refund
the same reservation twice. Pre-0016 costs are not invented; their conservative
reservations remain until the day rolls.

## Static provider context caching

`ASSISTANT_CACHE_ENABLED` defaults to false. Gemini's
[explicit cache API](https://ai.google.dev/api/caching) caches only fixed system
instructions, tool declarations and AUTO configuration. No farmer messages,
records, tool results, photos or identifiers enter creation. Dynamic contents
still require per-turn consent and ownership checks. The final tools-disabled
round is uncached to preserve its stricter policy.

Reuse is process-local, serialized and keyed by model, complete static context,
rate card and TTL. `ASSISTANT_CACHE_TTL_SECONDS` defaults to 300 (range 60–600).
Expiry/key changes invalidate the cache. Known invalid-cache generation responses
discard it for future turns without replaying generation. Shutdown attempts
deletion; provider TTL bounds leftovers after crashes/deletion failure. This is
not a promise to erase provider backups.

Both `cache_write_micro_usd_per_million` and
`cache_storage_micro_usd_per_million_token_hours` are required in the reviewed
rate card, including an explicit zero where appropriate. Creation is charged
once to its creating exchange using reported tokens and the full requested TTL,
conservatively even if deleted early. Each replica prices its own creation;
include this in the turn reserve. The receipt is marked before the request so
ambiguous creation stays unknown-cost.

Receipt modes are `created`, `reused`, `bypassed`, `unavailable`, `creating` and
`disabled`. Requested reuse does not prove a hit: reported
`cachedContentTokenCount` determines cached-input pricing; misses cost ordinary
input rates. Unsupported/too-short static context falls back to uncached
generation with a TTL-length creation cooldown. No prompt padding is performed.
Savings and model eligibility require live measurement, not synthetic tests.

## Read-only billing comparison

The CLI accepts a JSON array or newline-delimited JSON snapshot of Google's
[standard billing export](https://docs.cloud.google.com/billing/docs/how-to/export-data-bigquery-tables/standard-usage).
It does not fetch cloud data, execute BigQuery SQL or modify billing. Keep exports
under the ignored `.farmable-evidence/` directory, not in commits. Use a read-only
database role for the reporting command where available.

```bash
uv run python -m farmable_backend.assistant.reconcile \
  --export .farmable-evidence/billing.jsonl \
  --billing-account APPROVED_ACCOUNT_ID --project FARMABLE_PROJECT_ID \
  --service-id APPROVED_GEMINI_SERVICE_ID \
  --start 2026-09-24T00:00:00Z --end 2026-09-25T00:00:00Z
```

Supply the exact account/project/service IDs; descriptions are not used for fuzzy
matching. The required selected-row fields are `billing_account_id`, `project.id`,
`service.id`, `usage_start_time`, `usage_end_time`, `currency`, `cost`, `credits`
(each with `amount`), `cost_type`, `invoice.month` and `export_time`. Dates must be
timezone-aware. Input is bounded to 16 MiB/20,000 rows. Other scopes are ignored
and counted, not folded into Farmable totals. Non-USD selected rows require an
explicit future currency-conversion policy; they are rejected, not silently converted.
Intervals crossing a requested boundary are rejected rather than prorated.

The report retains exact decimal gross cost, signed credits and net cost separately.
It compares gross cost to the recorded text-call estimates, includes unknown/unscoped
calls and turns without receipts, and fingerprints the input snapshot and requested
scope. Rerunning a snapshot does not add charges again: this command is read-only.
Use a complete replacement snapshot when delayed charges or corrections arrive;
do not concatenate overlapping downloads. The importer cannot prove that an
operator-supplied file is complete or authentic.

Exit 0 means only `matches_recorded_estimate`. Exit 1 means a difference, missing
receipts or unknown costs; exit 2 means invalid/unavailable inputs. Every report
has `invoice_verified: false`: a usage-window export can span invoice months, and
late charges/credits are not proof of a finalized invoice. Compare with the final
provider statement separately. Files can include projectless account-level charges
that cannot safely be attributed to Farmable; a project report is not the entire bill.

## Remaining acceptance

This supplies durable usage/pricing, text settlement/recovery, static caching
and scoped export-comparison machinery.
Actual account/export validation, final invoice reconciliation and a validated
system-wide spend policy remain open. Gemini Live, crop.health and other providers
are not priced by this text ledger. A too-small reservation can still understate
spend; provider quotas and properly reviewed rates remain necessary. No code here
changes budget caps, automatically raises limits, refunds unknown costs or claims
to stop all spending based on a delayed export. No bill or paid call was used to
validate this implementation; the regression fixtures are synthetic.
