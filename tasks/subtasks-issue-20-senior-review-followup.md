# Issue #20: Senior review follow-up subtasks

**Parent PR:** [PR #61](https://github.com/ctrl-alt-elite-za/Farmable/pull/61)
**Parent issue:** [Issue #20](https://github.com/ctrl-alt-elite-za/Farmable/issues/20)
**Existing task breakdown:** [Issue #20 detailed subtasks](subtasks-issue-20-reference-data-forecasts-and-decision-backtest.md)
**Review source:** senior review comment on PR #61, 23 September 2026
**Status:** PR #61 is a tested foundation and remains separate from closing #20.

**Implementation checkpoint, 23 September 2026:** R01 is implemented and tested.
24 of 53 individual checklist items are complete; 29 remain open. R02's original
workbook coverage is audited for 2008–2024, with unknown publication dates recorded
as blockers; post-2024 harvest coverage still does not clear the source gate. R03
has complete modern-budget extracts, a frozen subtotal mapping, and named
calendar/cost blockers. The official ARC summer and winter booklets are now
downloaded and hashed in `ml/data/calendar_source_audit.json`; their crop topics
are identified, but regional applicability, release evidence, permission and
guideline yield midpoints remain unresolved. R04's strict historical-vintage
policy, selector and mutation/report-claim tests are implemented. No protocol
registration, import completion, or real result is claimed.

Evidence: [acceptance checks](../ml/ACCEPTANCE.md),
[source inventory](../ml/data/INVENTORY.md),
[market workbook audit](../ml/data/market_workbook_audit.json),
[budget review](../ml/data/BUDGET_REVIEW.md), and
[information policy and coverage contract](../ml/backtest/INFORMATION_POLICY.md).

This checklist converts the senior review into bounded implementation work. No real
forecast, recommendation, or decision result may be published before the protocol
has merged independently on `main`. Source inspection, schema work, synthetic
fixtures, and the report-safety fix may proceed before that gate.

## R01. Prevent unsupported historical claims

**Depends on:** none. **Owner:** ML/reporting owner. **Deliverable:** safe report period handling.

- [x] **R01.01** Define the required historical coverage contract: January 2012 through December 2024, all eight included crops, and the expected default/planting-month decision keys.
- [x] **R01.02** Add validation for historical ledgers before report generation; reject missing months, missing defaults, duplicate keys, or out-of-period rows.
- [x] **R01.03** Derive the displayed period from validated ledger coverage instead of hardcoding `2012–2024` in `render_sentence()`.
- [x] **R01.04** Make incomplete historical reports return an explicit insufficient-evidence status or raise a clear validation error.
- [x] **R01.05** Preserve synthetic fixture reporting without allowing it to masquerade as a complete historical result.
- [x] **R01.06** Add tests for partial historical ledgers, complete coverage, out-of-period rows, missing defaults, and the generated sentence.

**Completion evidence:** `test_reports.py` proves that partial data cannot generate a full-period historical claim.

## R02. Verify Johannesburg market history

**Depends on:** none. **Owner:** data research owner. **Deliverable:** accepted market source and coverage report.

- [x] **R02.01** Download representative Department of Agriculture Fresh Produce Market workbooks for 2012–2024.
- [x] **R02.02** Confirm workbook sheets contain Johannesburg, the required crops, monthly observations, units, and aggregation definitions.
- [x] **R02.03** Record publication or availability dates; do not infer planting-time availability from download dates.
- [x] **R02.04** Inventory pre-2012 training history and post-2024 harvest coverage for late-2024 plantings.
- [x] **R02.05** Measure missing months and crop aliases for all eight included crops.
- [x] **R02.06** Preserve FAOSTAT as a distinct farm-gate source unless an explicit issue amendment authorizes substitution.
- [x] **R02.07** Record source URLs, original filenames, retrieval dates, SHA-256 hashes, licence/redistribution status, units, flags, and unresolved gaps in `ml/data/SOURCES.md` and `ml/data/INVENTORY.md`.

**Completion evidence:** a per-crop/month coverage table and an explicit decision that either clears or blocks the historical Joburg input.

## R03. Verify costs and crop calendars

**Depends on:** R02. **Owner:** data research owner. **Deliverable:** normalized cost/calendar review sheet.

- [x] **R03.01** Obtain the dated Elsenburg budget for each of the eight included crops.
- [x] **R03.02** Extract budget region, update date, production period, yield units, VAT treatment, marketing costs, and every relevant subtotal.
- [x] **R03.03** Decide which subtotal is compatible with the gross-margin formula and document exclusions or inclusions.
- [x] **R03.04** Keep the processing-tomato budget caveat separate from fresh-market tomato prices.
- [ ] **R03.05** Verify planting windows, harvest offsets, occupied months, and guideline yield midpoints against the cited calendar sources.
- [x] **R03.06** Record regional assumptions, source versions, permissions, and unresolved calendar values.

**Completion evidence:** each crop has a traceable normalized cost and calendar record, or a named blocker.

## R04. Freeze the cost/CPI information policy

**Depends on:** R02–R03. **Owner:** lead/statistical reviewer. **Deliverable:** approved experiment rule.

- [x] **R04.01** Reproduce the CPI/cost ranking counterexample from the research notes.
- [x] **R04.02** Choose either historical cost/input vintages for a strict information-availability claim or an explicitly scoped fixed-modern-cost scenario.
- [x] **R04.03** Specify which CPI transformations are reporting-only and which, if any, may affect recommendation ranking.
- [x] **R04.04** Define the availability lag and revision policy for prices, CPI, costs, and calendars.
- [x] **R04.05** Update the issue wording or generated sentence if the selected scenario cannot support the literal planting-time claim.
- [x] **R04.06** Add synthetic future-data mutation tests for the approved decision policy.

**Completion evidence:** a reviewed decision memo or protocol section with no unresolved information-availability contradiction.

## R05. Finalize and merge the protocol

**Depends on:** R01, R04, and the existing contract/methodology tasks. **Owner:** lead. **Deliverable:** independently merged `ml/backtest/PROTOCOL.md`.

- [ ] **R05.01** Replace the draft with a registered protocol containing period, crops, exclusions, source vintages, formulas, forecast selection, missing-data rules, metrics, bootstrap, and sentence template.
- [ ] **R05.02** Include the approved cost/CPI policy and all budget/calendar assumptions.
- [ ] **R05.03** Review every rule against the Issue #20 acceptance criteria.
- [ ] **R05.04** Open a protocol-only PR with no real decision results.
- [ ] **R05.05** Merge the protocol on `main` before running any real decision evaluation.
- [ ] **R05.06** Record the merged protocol commit and verify the history gate against the actual mainline ancestry.

**Completion evidence:** `ml/backtest/check_protocol_first.py --check-ready` passes against the merged mainline protocol.

## R06. Implement reference-data imports

**Depends on:** R02–R03, current-main schema reconciliation, and the existing package contracts. **Owner:** backend/data implementation owner. **Deliverable:** validated ORM imports.

- [ ] **R06.01** Reconcile the current #8 reference schema, identifiers, migration head, and constraints.
- [ ] **R06.02** Add only required additive ORM models/fields and migrations.
- [ ] **R06.03** Implement market-price, calendar, and cost import commands.
- [ ] **R06.04** Validate the complete source before opening the write transaction.
- [ ] **R06.05** Persist source hashes, parser version, row counts, and imported records atomically.
- [ ] **R06.06** Make identical imports no-ops and changed-source imports explicit conflicts.
- [ ] **R06.07** Add rollback, retry, natural-key uniqueness, and concurrent import tests.
- [ ] **R06.08** Implement and pass `test_import_idempotent`, migration safety, and no-raw-SQL checks.

**Completion evidence:** repeated identical imports produce one logical dataset/import and failed imports leave no partial rows.

## R07. Build the real runner and Colab workflow

**Depends on:** R05–R06 and the existing forecast/decision modules. **Owner:** ML execution owner. **Deliverable:** credential-free gated execution path.

- [ ] **R07.01** Add a real-data runner that loads only approved canonical inputs and the merged protocol.
- [ ] **R07.02** Enforce the protocol history gate before any real decision evaluation.
- [ ] **R07.03** Add a credential-free Colab notebook that installs pinned dependencies and verifies source hashes.
- [ ] **R07.04** Generate the historical forecast ledger and forecast evaluation artifact.
- [ ] **R07.05** Generate the decision ledger using frozen recommendations before reading realized outcomes.
- [ ] **R07.06** Keep the historical ledger separate from the #21 deployment snapshot.
- [ ] **R07.07** Include code, protocol, configuration, input hashes, seeds, dependency versions, and caveats in the run manifest.

**Completion evidence:** a clean synthetic run exercises the same runner path without database access or credentials; the real entry point refuses to run before the protocol gate.

## R08. Generate and validate real artifacts

**Depends on:** R07 and sufficient verified source coverage. **Owner:** lead with independent reviewer. **Deliverable:** reviewed real-data result run.

- [ ] **R08.01** Run the forecast and decision workflow only after the protocol merge.
- [ ] **R08.02** Produce `forecasts.parquet`, `forecast_backtest.json`, `decision_backtest.json`, `decision_backtest.md`, `slide_sentence.txt`, the decision ledger, and the manifest.
- [ ] **R08.03** Validate all eight defaults plus pooled metrics, denominators, null reasons, exclusions, and caveats.
- [ ] **R08.04** Verify that the generated period and planting-time wording match actual validated coverage and the approved cost/CPI policy.
- [ ] **R08.05** Run independent reproducibility checks and compare artifact bytes.
- [ ] **R08.06** Review weak classes, negative results, source provenance, and redistribution status before publication.
- [ ] **R08.07** Open the results PR with complete acceptance evidence; do not close #20 if any criterion remains unmet.

**Completion evidence:** a reproducible results directory and reviewable evidence for every Issue #20 acceptance criterion.

## Dependency order

```text
R01 ───────────────┐
R02 ──> R03 ──> R04 ──> R05 ──> R06 ──> R07 ──> R08
                   └───────────────────────────────┘
```

R01 is an immediate review fix and can land independently. R02 and R03 are
source-verification gates. R04 and R05 must settle the information policy before
real recommendations. R06–R08 are blocked by the verified inputs and merged
protocol. Synthetic tests may be added throughout, but they must not be presented
as real historical evidence.

## Definition of done

- The report generator cannot make a full-period historical claim from partial data.
- All eight crops have verified, traceable market, calendar, and cost inputs or explicit documented exclusions.
- `ml/backtest/PROTOCOL.md` is merged before real results exist.
- Reference imports are transactional and idempotent.
- The runner is credential-free, reproducible, and protocol-gated.
- Real artifacts and the generated sentence match validated coverage and the approved information policy.
- Issue #20 is closed only after all acceptance evidence is reviewed and complete.
