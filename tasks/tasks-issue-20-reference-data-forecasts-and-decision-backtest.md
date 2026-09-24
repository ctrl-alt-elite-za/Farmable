# Tasks: Reference data, forecasts, and decision backtest

**Source:** [Issue #20](https://github.com/ctrl-alt-elite-za/Farmable/issues/20) and the [PRD](../docs/PRD-issue-20-reference-data-forecasts-and-decision-backtest.md)  
**Status:** Foundation partly implemented locally; task groups remain open (see the 23 September checkpoint in the verification notes)  
**Reviewed:** 22 September 2026  
**Dependencies:** [#8](https://github.com/ctrl-alt-elite-za/Farmable/issues/8) for reference schema; output contract consumed by [#21](https://github.com/ctrl-alt-elite-za/Farmable/issues/21)

This document breaks the PRD into separately reviewable changes. Completing research does not mean the input datasets, implementation, or acceptance tests have passed. Do not run the real decision backtest until the protocol has merged in its own PR. Synthetic fixtures and source-coverage checks may run earlier.

## 1. Delivery order and ownership

| Work package                                 | Depends on                              | Suggested owner                                     | Review boundary                          |
| -------------------------------------------- | --------------------------------------- | --------------------------------------------------- | ---------------------------------------- |
| T01–T03: baseline, sources, contracts        | Nothing                                 | Lower-cost agent for inspection; lead for decisions | Evidence and schema contracts            |
| T04–T05: methodology and protocol            | T02–T03                                 | Lead                                                | Protocol-only PR merged on main          |
| T06–T08: environment, canonical data, CPI    | T02–T04                                 | Lower-cost implementation agents                    | Small infrastructure/data PRs            |
| T09: reference imports                       | T01, T03, T07                           | Backend agent                                       | ORM import PR with database tests        |
| T10–T12: forecasts and temporal selection    | T06–T08, frozen methodology             | Model agent; lead reviews leakage                   | Forecast implementation PRs              |
| T13–T15: decisions, statistics, reports      | T04, T06–T08, T12                       | Separate bounded agents after contracts settle      | Synthetic backtest implementation PRs    |
| T16–T18: snapshot, reproducibility, notebook | T10–T15                                 | Lower-cost implementation agent                     | Consumer and execution integration PRs   |
| T19: real run and results                    | All earlier tasks, including merged T05 | Lead with independent review                        | Results PR; complete acceptance evidence |

Keep ownership at file/module boundaries when delegating. Do not ask multiple agents to change the same shared config or schema simultaneously. The lead owns statistical choices, schema reconciliation, cross-module contracts and final evidence review. Lower-cost agents can handle bounded research, parsers, command adapters, synthetic tests and report generators after those contracts are fixed.

## 2. Implementation checklist

### T01. Establish the implementation base

**Output:** source revision and schema inventory. **Depends on:** none.

- [ ] Preserve existing `.gitignore`, planning documents and unrelated working-tree changes.
- [ ] Inspect the intended current main revision and the actual implementation delivered by #8 before creating an implementation branch.
- [ ] Locate reference tables, constraints, crop identifiers and migration head; distinguish missing local changes from genuinely missing schema.
- [ ] Record which #8 tables can be reused and which additive changes are necessary. Do not create duplicate reference models based only on the stale checkout.

**Done when:** the reference import design names actual model classes, keys and migration dependencies at a recorded commit.

### T02. Verify and inventory public source files

**Output:** source/coverage inventory feeding `ml/data/SOURCES.md`. **Depends on:** none.

- [ ] Locate the exact `sa-fresh-produce-market-analysis` repository or supplied files and pin its revision.
- [ ] Inspect the existing cached `origin/issue-20-reference-data` revision `69ff3904dd308f3859b0d4115fac2cac92429c15` before collecting inputs again. Verify its staged GDARD calendar against original sources.
- [ ] Resolve the branch's FAOSTAT farm-gate substitution and combined pumpkin/butternut series explicitly; neither silently satisfies historical Joburg butternut prices. Check anomalous values against source units/flags rather than smoothing them until results improve.
- [ ] Inspect representative official Department of Agriculture archive workbooks for monthly Joburg coverage, then inventory the complete period if suitable.
- [ ] Identify Joburg price files, calendars, yield guidelines and Elsenburg budget files; record source URLs, retrieval dates and SHA-256 values.
- [ ] Inspect headers, units, crop aliases, missing months, budget years and geographic assumptions without calculating switching outcomes.
- [ ] Where daily totals are aggregated, compute value/weight consistently and prevent carried-forward quotes or cumulative month-to-date totals from being counted repeatedly.
- [ ] Count pre-2012 training months, 2012–2024 planting coverage and harvest-price coverage after December 2024.
- [ ] Verify the eight cost-backed crops individually; record excluded beetroot/pumpkins and processing-tomato caveat.
- [ ] Verify permission to redistribute each input; public availability alone does not establish a licence.
- [ ] Produce a per-crop coverage table and explicit unresolved-source list.

**Done when:** every proposed input has a traceable source and usable schema, or a named blocker. Do not mark a dataset verified from a search result alone.

### T03. Freeze input and output contracts

**Output:** versioned schemas and tiny synthetic fixtures. **Depends on:** T01–T02.

- [ ] Define canonical crop IDs, units, observation dates, availability dates, region and source versions.
- [ ] Define planting-to-harvest offsets separately from occupied months and document conversions from day-based guidelines.
- [ ] Agree a separate historical forecast ledger and deployment snapshot contract with #21.
- [ ] Specify the snapshot's complete crop × 12-month grid, month meaning, as-of cutoff, positive prices and ordered quantiles.
- [ ] Fix currency basis explicitly: historical 2025-rand reporting must not be silently consumed as current nominal market prices.
- [ ] Decide the deployment crop universe; do not assume the eight cost-backed backtest crops are the complete consumer universe.
- [ ] Confirm the proposed split between `apps/ml-service/` implementation and `ml/` adapters/data/artifacts, or record an agreed path adjustment to the issue.

**Done when:** both offline workflows and the #21 consumer can validate the same snapshot fixture without inferred units or month semantics.

### T04. Resolve statistical choices before results

**Output:** fixed methodological decisions with worked synthetic examples. **Depends on:** T02–T03.

- [ ] Resolve the interaction between modern fixed cost/yield assumptions, the 2025 CPI base and literal no-look-ahead criteria. Prove invariance with synthetic crop rankings rather than assuming a reporting conversion is harmless.
- [ ] Define availability lags and treatment of revisions; distinguish observation dates from information actually available at planting.
- [ ] Fix training minimums, lag features, forecast horizons, temporal validation windows and method-selection ties from coverage evidence.
- [ ] Define numerical tie tolerance, quantile interpolation, cost subtotal/VAT treatment and whether nursery time occupies the farmer's land. Preserve guideline mid yield separately from budget yield.
- [ ] Decide whether the last-year baseline is an eligible production method or a diagnostic comparator; obtain explicit resolution of ambiguous issue wording.
- [ ] Define missing-data eligibility without retrospectively substituting a different recommendation.
- [ ] Fix metric denominators, percentage gains for nonpositive default margins, null values and worst-loss sign conventions.
- [ ] Choose the bootstrap resampling unit, block length if applicable, replicates, seed and treatment of empty-switch replicates; document dependence across defaults and years.
- [ ] Define handling when all predictions are negative or when headline statistics are undefined.

**Done when:** no result-dependent choice remains hidden in the planned notebook. Any necessary change to the issue's acceptance wording is explicit, not an implementation shortcut.

### T05. Merge the protocol and implement its history gate

**Output:** `ml/backtest/PROTOCOL.md` plus tested history checker. **Depends on:** T04.

- [ ] Write the fixed period, crops, assumptions, formulas, selection rule, metrics and exact sentence template.
- [ ] Merge the protocol in its own PR before any real decision backtest execution. The merge is an external milestone, not satisfied by a local draft.
- [ ] Implement `ml/backtest/check_protocol_first.py` with mainline ancestry/order checks, including squash/merge histories.
- [ ] Require the executed protocol content/version to match a merged version; merely proving that some old protocol exists is insufficient.
- [ ] Reject missing/shallow history and results introduced before or in the same mainline change as the first protocol.
- [ ] Define a preparation-state result before the first results commit, distinct from completed protocol-before-results acceptance evidence.
- [ ] Add temporary-repository tests for valid ordering, same-commit introduction, unmerged amendment and missing history.

**Done when:** the merged protocol is identified and the real-run entry point enforces its gate. Later amendments preserve both rule sets and their results.

### T06. Add the offline package and make checks discover it

**Output:** installable offline package and pinned environment. **Depends on:** T03.

- [ ] Add `apps/ml-service/pyproject.toml` and an importable `farmable_ml` package using the existing repository's supported Python version.
- [ ] Add only required offline dependencies; resolve and pin tested NumPy/pandas/PyArrow/LightGBM versions for local execution and Colab.
- [ ] Ensure the Colab install does not install or initialize backend database integrations.
- [ ] Add thin `ml/forecast/` and `ml/backtest/` CLI adapters and synthetic tests using the same installed implementation.
- [ ] Update root package/workspace configuration, Make targets, CI scope detection, pre-push selection and pytest discovery to include both ML roots.
- [ ] Add a narrow tracked-artifact exception for approved `ml/forecast/results/` Parquet files; the current global `*.parquet` ignore rule would hide required results. Preserve unrelated ignore rules.
- [ ] Add scope regression tests proving an `ml/`-only change runs the relevant checks.
- [ ] Review `docs/ci.md` before changing CI configuration; no privilege or required-check activation is needed for this task by default.

**Done when:** fresh documented setup can import the package and repository checks actually execute its tests.

### T07. Implement pure input normalization

**Output:** canonical data loaders and validation report. **Depends on:** T02–T03, T06.

- [ ] Parse market prices with explicit units and availability metadata.
- [ ] Parse calendar/yield and cost records with stable crop aliases and provenance.
- [ ] Validate duplicate/conflicting natural keys, finite values, required fields and unit conversions.
- [ ] Keep parsers independent of the database; reuse them from the backend import layer without importing backend code into Colab.
- [ ] Test documented source-shaped fixtures, invalid rows and kg/tonne/package conversions.

**Done when:** the same input bytes produce the same validated canonical rows and source hashes, with actionable failures on invalid inputs.

### T08. Commit CPI and implement price-basis conversion

**Output:** committed CPI snapshot, provenance and tested conversion functions. **Depends on:** T02, T04, T06.

- [ ] Download the selected level-index series; distinguish index levels from inflation percentage series.
- [ ] Use a verified comparable fallback for a full-year 2025 base: the specified FRED series stops in January 2025. Verify a consistent historical Stats SA/OECD series and any rebasing rather than splicing raw index values.
- [ ] Verify required historical observations and the full selected 2025 reporting base; fail on unavailable months rather than inventing observations.
- [ ] Record vintage, monthly dates, download URL/date and SHA-256 in `SOURCES.md`.
- [ ] Implement separate planting-time and retrospective reporting transformations according to the frozen protocol.
- [ ] Test a known 2012 conversion using the committed file, cost-budget date mapping, incomplete CPI, double-adjustment prevention and future-data mutation.

**Done when:** `test_cpi_adjustment` passes and the decision pipeline passes the agreed strict information-cutoff checks.

### T09. Implement transactional ORM reference imports

**Output:** backend import commands and integration tests. **Depends on:** T01, T03, T07.

- [ ] Add only needed additive models/migrations aligned to #8; declare constraints through SQLAlchemy ORM/Alembic operations without handwritten SQL.
- [ ] Add import commands for monthly prices, crop calendars and Elsenburg costs.
- [ ] Extend the existing `farmable_backend.manage` command surface or document a deliberate new entry point; preserve existing vision migration/ORM parity tests while adding reference schema coverage.
- [ ] Validate before writing, then atomically persist records and source/hash audit metadata.
- [ ] Implement identical-file no-op behavior and explicit changed-file/parser-version conflict policy.
- [ ] Test retries, duplicates, transaction rollback and natural-key conflicts against the supported database fixture.

**Done when:** `test_import_idempotent` and relevant migration, lint and no-raw-SQL checks pass; failed imports leave no partial data.

### T10. Implement historical ranges and the seasonal baseline

**Output:** deterministic simple forecasters. **Depends on:** T04, T06–T08.

- [ ] Build a single cutoff-filtering layer and apply it before feature construction or training.
- [ ] Implement per-crop/month historical P10/P50/P90 in the agreed price basis.
- [ ] Implement same-target-month-last-year prediction only when that observation is available at the planting cutoff.
- [ ] Apply fixed minimum-history and fallback/unsupported policies.
- [ ] Test exact quantiles, year boundaries, unavailable last-year targets and mutations after cutoff.

**Done when:** the simple methods produce correct forecast records on hand-checkable fixtures and pass `test_no_lookahead_forecast`.

### T11. Implement the LightGBM challenger

**Output:** fixed-configuration quantile models. **Depends on:** T10.

- [ ] Build horizon-aware features available at planting; fit learned transformations inside each training window.
- [ ] Train separate 0.10/0.50/0.90 quantile objectives with pinned versions and deterministic CPU settings.
- [ ] Apply the protocol's quantile-crossing correction identically during validation and export.
- [ ] Test feature cutoffs, missing-history handling, ordered outputs and repeat execution.

**Done when:** no training or preprocessing stage reads post-cutoff observations, including validation outcomes not yet available.

### T12. Implement temporal evaluation and method selection

**Output:** `forecast_backtest.json` and historical forecast ledger. **Depends on:** T10–T11.

- [ ] Evaluate methods on identical eligible targets using the frozen loss function and chronological folds.
- [ ] Reconstruct each validation forecast at its own historical origin, not with a model fitted once at the later selection cutoff. Record method failures on the common target set instead of silently dropping difficult targets.
- [ ] Select each historical decision's method using only validation outcomes available before its cutoff.
- [ ] Record loss by crop/method, baseline comparison, interval diagnostics, sample counts and unsupported windows.
- [ ] Test controlled winners, ties, changed future observations and prohibition of a single full-period winner reused in earlier years.

**Done when:** `test_method_selection_picks_backtest_winner` passes and the selection ledger can be independently reconstructed.

### T13. Implement eligibility and the decision ledger

**Output:** one traceable row per evaluated default/planting-month pair. **Depends on:** T04, T07–T08, T12.

- [ ] Enumerate January 2012–December 2024 plantings and the frozen in-season candidate set.
- [ ] Compute predicted gross margin with each crop's own yield, cost, harvest timing and occupied duration.
- [ ] Freeze the maximum-margin recommendation and deterministic tie-break before reading realized harvest prices.
- [ ] Record default, recommendation, no-switch/switch, actual margins, gains and eligibility/skip reasons.
- [ ] Handle missing recommended outcomes without selecting a replacement and retain coverage counts for late-2024 harvests.
- [ ] Test formula examples, negative margins, duration differences, ties and future-outcome mutations.

**Done when:** `test_gross_margin_formula` and `test_no_lookahead_recommendation` pass on synthetic fixtures.

### T14. Implement metrics and uncertainty

**Output:** validated eight-crop-plus-pooled statistics. **Depends on:** T13.

- [ ] Compute required rates, median rand/percentage gains, p10, worst loss and 90% median interval using frozen definitions.
- [ ] Preserve losses/ties and record counts excluded only from undefined percentage calculations.
- [ ] Compute pooled values from decision rows, not crop-level averages.
- [ ] Implement seeded dependence-aware bootstrap and explicit undefined-interval behavior.
- [ ] State the inferential assumptions behind the required confidence interval. With at most 13 planting-year clusters, report that limitation; preregister any leave-one-year-out or block-resampling sensitivity check before seeing outcomes.
- [ ] Test manual expected results, unequal crop counts, no switches, zero/negative baselines and reproducible resampling.

**Done when:** every required field exists for every crop and pooled, with valid null reasons and reconstructable denominators.

### T15. Generate reports and the slide sentence

**Output:** `decision_backtest.json`, `.md` table and `slide_sentence.txt`. **Depends on:** T14.

- [ ] Generate the alphabetical eight-crop table and pooled results from one statistics object.
- [ ] Include all input hashes, exclusions and caveats automatically.
- [ ] Generate N/X/Y/A/B directly from their specified metrics using shared rounding.
- [ ] Handle insufficient evidence according to the protocol; never invent an eight-crop range or manually improve a negative result's wording.
- [ ] Add `test_table_lists_every_default`, `test_slide_sentence_from_results` and schema validation.

**Done when:** every report number can be traced to the same ledger and the required template is satisfied or explicitly reported unmet.

### T16. Export the deployment snapshot for #21

**Output:** import-ready `forecasts.parquet` and validator. **Depends on:** T03, T12.

- [ ] Generate the complete agreed crop × 12-month snapshot at a recorded final cutoff, separately from historical evaluation rows.
- [ ] Validate exact columns/types, unique keys, positive finite prices, P10 ≤ P50 ≤ P90, units and as-of metadata.
- [ ] Implement the exact `python ml/forecast/validate_output.py <path>` acceptance entry point.
- [ ] Test a valid consumer fixture, missing months, duplicates, negative/zero prices, crossed quantiles and unit/version mismatches.
- [ ] Document that #21 owns database activation and comparison to the previous active run, including its 50% P50-change guard.

**Done when:** the exported snapshot satisfies the agreed #21 contract; historical ledger files cannot accidentally pass as deployment snapshots.

### T17. Make artifact serialization reproducible

**Output:** deterministic run IDs, manifests and byte-stable files. **Depends on:** T12, T15–T16.

- [ ] Hash canonical inputs/configuration/code/protocol into the run ID.
- [ ] Fix ordering, precision, JSON key handling, Parquet writer/compression settings and environment metadata.
- [ ] Exclude volatile timestamps and machine paths from deterministic artifacts.
- [ ] Execute two clean synthetic runs in the supported environment and compare all output bytes, including reports and manifests.
- [ ] Record the tested platform/runtime bounds; do not claim arbitrary-platform determinism from seeds alone.

**Done when:** `test_reproducible_output` compares actual files from independent runs and passes.

### T18. Build and verify the Colab workflow

**Output:** a thin credential-free notebook and run instructions. **Depends on:** T05–T08, T12–T17.

- [ ] Install the package and pinned dependencies at an explicit revision with no backend/database initialization.
- [ ] Verify public input hashes, protocol revision/main history and environment before execution.
- [ ] Run tests, forecast generation, gated decision evaluation and artifact packaging through shared CLI functions.
- [ ] Keep notebook outputs cleared; do not put credentials or automatic publishing in cells.
- [ ] Smoke-test a clean synthetic notebook run and document the real-data entry point.
- [ ] Run secret scanning over both `ml/` and the implementation root, since the code is split across paths.
- [ ] Preserve the issue's directory-scan evidence and also run the repository's pinned full-history Gitleaks workflow equivalent from `.github/workflows/gitleaks.yml`; a clean working-tree scan alone is insufficient.

**Done when:** a fresh credential-free runtime can reproduce the synthetic workflow and refuses an unmerged/mismatched protocol for a real run.

### T19. Run the registered experiment and publish evidence

**Output:** forecast and backtest results PR, with acceptance evidence. **Depends on:** all earlier tasks.

- [ ] Confirm the merged protocol gate and frozen input hashes before executing the first real decision evaluation.
- [ ] Run the workflow in Colab and repeat it in the pinned supported environment to verify output equality.
- [ ] Inspect coverage, losses, excluded decisions, method performance and every default crop; retain negative findings.
- [ ] Run `make lint`, `make typecheck`, `make test`, `pytest ml/forecast ml/backtest`, the forecast validator, ORM import tests and secret scanning.
- [ ] Open the results PR with manifests, ledgers, reports and caveats; verify protocol-before-results against the eventual mainline history.
- [ ] Hand the snapshot contract and validated artifact to #21 without implementing its importer here.
- [ ] Map every issue acceptance criterion to a test/result; explicitly list any unmet criterion instead of marking the issue complete.

**Done when:** real artifacts are committed through the required PR workflow and all acceptance evidence is reviewed, including the protocol's earlier mainline introduction.

## 3. Acceptance coverage

| Issue requirement                                     | Tasks         |
| ----------------------------------------------------- | ------------- |
| Public source hashes and idempotent reference imports | T02, T07, T09 |
| Committed CPI and `test_cpi_adjustment`               | T08           |
| No look-ahead in forecasts and recommendations        | T04, T10–T13  |
| Walk-forward winner selection                         | T12           |
| Protocol merged before real execution/results         | T05, T18–T19  |
| Gross margin formula                                  | T13           |
| Eight defaults, pooled metrics, exclusions/caveats    | T14–T15       |
| Every-default table and generated sentence tests      | T15           |
| Validated Parquet output                              | T16           |
| Byte-identical output                                 | T17, T19      |
| Credential-free Colab and secret scanning             | T18–T19       |
| Repository lint/typecheck/test integration            | T06, T19      |

## 4. Research findings and open dependencies

Research evidence and unresolved questions are recorded in the accompanying [verification notes](../docs/research-issue-20-implementation-verification.md). Read those before assigning implementation tasks. Proposed statistical settings remain proposals until T04–T05 fix them; source discovery remains incomplete wherever the evidence notes say so.
