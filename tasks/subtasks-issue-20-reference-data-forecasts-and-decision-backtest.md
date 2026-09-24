# Issue #20: Detailed subtask checklist

**Parent plan:** [Implementation tasks](tasks-issue-20-reference-data-forecasts-and-decision-backtest.md)  
**Requirements:** [PRD](../docs/PRD-issue-20-reference-data-forecasts-and-decision-backtest.md)  
**Evidence:** [Research and verification notes](../docs/research-issue-20-implementation-verification.md)  
**Status:** Tested components implemented locally; checked subtasks have local evidence in `ml/ACCEPTANCE.md`. Main task groups remain open until all dependencies and acceptance evidence are satisfied.  
**Created:** 22 September 2026

Each checkbox has a stable ID for assignment, commits and review. Complete a subtask only when its stated result exists. Record evidence as a file, test result or PR link. Module filenames below are proposed and should be finalized in T03. Existing research is input to these tasks; it must be checked against the implementation revision rather than repeated unnecessarily.

The protocol must merge in its own PR before running the decision backtest on real data. Source inventories and synthetic tests can run earlier. An unresolved methodological choice remains open until it is recorded in the protocol; elapsed time or passing unrelated tests does not resolve it.

## T01. Establish the implementation base

**Depends on:** none. **Deliverable:** baseline and schema inventory. **Owner:** lead, with inspection delegated.

- [ ] **T01.01** Record current branch, HEAD commit and working-tree status.
- [ ] **T01.02** Identify existing user edits and planning files that must be preserved.
- [ ] **T01.03** Identify the intended main revision and distinguish cached remote refs from current remote state.
- [ ] **T01.04** Find the PR/commit that delivered #8 and compare it with the intended implementation base.
- [ ] **T01.05** List reference ORM classes actually present at that base.
- [ ] **T01.06** List reference-table natural keys, foreign keys and constraints.
- [ ] **T01.07** Identify the Alembic head and any concurrent migrations affecting reference data.
- [ ] **T01.08** Record missing schema separately from schema already implemented on another branch.
- [ ] **T01.09** Create the dedicated implementation branch or isolated worktree from the chosen base without overwriting unrelated changes.
- [ ] **T01.10** Save the baseline inventory with source revision and model/migration paths for T03 and T09.

**Completion evidence:** recorded base commit and a table-by-table reuse/gap list.

## T02. Verify public inputs and coverage

**Depends on:** none. **Deliverable:** source manifest and feasibility report. **Owner:** data research agent; lead resolves substitutions.

- [ ] **T02.01** Inventory files in cached `origin/issue-20-reference-data` at `69ff3904dd308f3859b0d4115fac2cac92429c15` before collecting them again.
- [ ] **T02.02** Confirm the exact source repository intended by the issue and record its revision.
- [ ] **T02.03** Record source URL, original filename and retrieval date for each candidate input.
- [ ] **T02.04** Calculate SHA-256 for each source file without altering its bytes.
- [ ] **T02.05** Record redistribution terms or unresolved permission status for each input.
- [ ] **T02.06** Inspect representative Department of Agriculture workbooks for monthly, crop-specific Joburg observations.
- [ ] **T02.07** If suitable, inventory the remaining required years and available pre-2012 training history.
- [ ] **T02.08** Count observations and missing months by crop, market and year.
- [ ] **T02.09** Count available harvest outcomes after December 2024 for late-2024 plantings.
- [ ] **T02.10** Identify daily trading dates versus scrape dates and document carried-forward observations.
- [ ] **T02.11** Identify daily versus cumulative month-to-date totals so aggregation cannot double-count sales.
- [ ] **T02.12** Record original price, weight and package units, plus documented conversion factors.
- [ ] **T02.13** Document the staged FAOSTAT farm-gate/Joburg wholesale mismatch and decide whether to find matching history or propose an explicit scope change.
- [ ] **T02.14** Investigate combined pumpkin/butternut labels and anomalous FAOSTAT values against original units and flags; preserve the raw values.
- [ ] **T02.15** Locate one identified Elsenburg budget for each of the eight included crops.
- [ ] **T02.16** Extract budget region, update date, yield unit, growing period, VAT treatment and named cost subtotals into a review sheet.
- [ ] **T02.17** Verify staged calendar planting windows and yield ranges against their cited GDARD/ARC source pages.
- [ ] **T02.18** Record missing calendar values, regional applicability and the processing-tomato caveat.
- [ ] **T02.19** Identify a CPI level-index source covering the historical period and selected 2025 base; record the specified FRED series' coverage limitation.
- [ ] **T02.20** Produce the per-crop feasibility report with unresolved inputs, excluding any real switching-profit calculations.

**Completion evidence:** every required input is sourced and inspected or explicitly blocked; source discovery alone is insufficient.

## T03. Define input and output contracts

**Depends on:** T01, T02. **Deliverable:** versioned schemas and synthetic examples. **Owner:** lead.

- [ ] **T03.01** Define canonical IDs for included crops and excluded crops.
- [ ] **T03.02** Define an explicit alias map and reject ambiguous combined commodities.
- [ ] **T03.03** Specify market-price fields, natural keys, units and provenance fields.
- [ ] **T03.04** Specify observation dates, availability timestamps and revision/vintage fields.
- [ ] **T03.05** Specify calendar region, planting windows, yield ranges and guideline mid-yield fields.
- [ ] **T03.06** Specify sowing/transplant timing, harvest offsets and occupied duration as distinct concepts.
- [ ] **T03.07** Specify cost-budget fields, subtotal definition, date basis and source version.
- [ ] **T03.08** Specify CPI dates, index basis, vintage and conversion metadata.
- [ ] **T03.09** Define the historical forecast ledger schema, including origin, target and selected method.
- [ ] **T03.10** Define the decision ledger schema, including eligibility and missing-outcome states.
- [ ] **T03.11** Define the deployment snapshot's crop universe and exact crop-by-12-month keys with #21's contract.
- [ ] **T03.12** Define snapshot month semantics, as-of cutoff, currency, price unit and price basis.
- [ ] **T03.13** Define JSON metric shapes, null reasons and manifest schema versions.
- [ ] **T03.14** Create tiny valid and invalid synthetic records for each schema.
- [ ] **T03.15** Finalize implementation/data/artifact paths and public CLI entry points while preserving the issue's acceptance commands.

**Completion evidence:** contracts and fixtures are sufficient to implement producers and consumers without inferred field meanings.

## T04. Resolve the experiment's statistical rules

**Depends on:** T02, T03. **Deliverable:** fixed decisions for the protocol. **Owner:** lead with methodology review.

- [ ] **T04.01** Write the precise question the simulation estimates, including its population of default/planting-month decisions.
- [ ] **T04.02** Reproduce the synthetic CPI/cost ranking counterexample from the research notes.
- [ ] **T04.03** Choose a coherent historical-information or fixed-scenario design and resolve any conflict with the literal issue requirements.
- [ ] **T04.04** Specify which values may use retrospective CPI and which may enter recommendation ranking.
- [ ] **T04.05** Fix availability lags and treatment of observations revised after a historical cutoff.
- [ ] **T04.06** Fix how guideline mid yield is derived and keep it distinct from the budget's own yield assumption.
- [ ] **T04.07** Choose the cost subtotal, VAT convention and treatment of marketing costs.
- [ ] **T04.08** Define nursery occupancy, day-to-month conversion and fractional growing-period handling.
- [ ] **T04.09** Fix minimum training observations, lookback policy and supported forecast horizons from source coverage.
- [ ] **T04.10** Fix lag features and temporal validation windows, including outcome-availability rules.
- [ ] **T04.11** Fix quantile interpolation, crossing correction and the exact forecast-loss formula.
- [ ] **T04.12** Decide whether the previous-year baseline is a selectable method or benchmark only.
- [ ] **T04.13** Fix selection granularity, loss aggregation, numerical tie tolerance and tie-break order.
- [ ] **T04.14** Define behavior for missing candidate forecasts, missing actual prices and all-negative predictions.
- [ ] **T04.15** Define denominators for decisions, switches, wins and percentage gains.
- [ ] **T04.16** Define null behavior, worst-loss sign and percentile interpolation.
- [ ] **T04.17** Choose bootstrap sampling units, dependence assumptions, seed and replicate count.
- [ ] **T04.18** Define empty-resample handling and minimum valid resamples for a confidence interval.
- [ ] **T04.19** Preregister any sensitivity analysis and headline behavior when a crop has no defined switch-win rate.
- [ ] **T04.20** Review the slide's planting-time claim and document any required issue clarification before protocol finalization.

**Completion evidence:** written rules and worked synthetic examples, with no unresolved result-dependent choices.

## T05. Register the protocol and enforce ordering

**Depends on:** T04. **Deliverable:** independently merged protocol and history checker. **Owner:** lead; checker implementation can be delegated.

- [ ] **T05.01** Draft `ml/backtest/PROTOCOL.md` from the finalized T04 decisions.
- [ ] **T05.02** Include period, crop set, exclusions, formulas, metrics and the exact sentence template.
- [ ] **T05.03** Define protocol versioning and dated-amendment rules that preserve old/new results.
- [ ] **T05.04** Review the protocol against each relevant #20 acceptance criterion.
- [ ] **T05.05** Prepare and open a protocol-only PR with no real decision results.
- [ ] **T05.06** Record the actual mainline merge commit once the protocol is merged.
- [x] **T05.07** Implement lookup of the protocol's first mainline introduction.
- [x] **T05.08** Implement lookup of the first mainline results introduction and compare ancestry/order.
- [ ] **T05.09** Verify that the protocol content used by a run matches a merged protocol version.
- [x] **T05.10** Reject shallow/missing history, same-change introductions and unmerged amendments.
- [x] **T05.11** Distinguish pre-results preparation status from final protocol-before-results acceptance.
- [ ] **T05.12** Add temporary Git-repository fixtures for merge, squash, invalid-order and missing-history cases.

**Completion evidence:** merged protocol reference plus passing history-checker fixtures. T18 wires the checker into execution.

## T06. Package the offline implementation and wire checks

**Depends on:** T03. **Deliverable:** installed package and effective local/CI checks. **Owner:** tooling agent.

- [x] **T06.01** Create the ML package manifest using the repository's supported Python version.
- [ ] **T06.02** Create importable `farmable_ml` data, forecast and backtest modules.
- [ ] **T06.03** Add required NumPy, pandas, PyArrow and LightGBM dependencies and resolve compatible versions.
- [x] **T06.04** Update the workspace/lock configuration for local installation.
- [ ] **T06.05** Produce exact Colab dependency pins consistent with the tested package.
- [ ] **T06.06** Verify offline installation does not initialize or require the backend/database.
- [ ] **T06.07** Add thin CLI entry points under `ml/forecast/` and `ml/backtest/`.
- [x] **T06.08** Extend pytest discovery to the ML tests.
- [x] **T06.09** Extend `make test` so it actually executes ML tests.
- [x] **T06.10** Extend type-check targets beyond the existing vision-only ML target.
- [x] **T06.11** Extend CI scope detection for `ml/` and retain `apps/ml-service/` coverage.
- [x] **T06.12** Extend pre-push path selection and ML test execution.
- [x] **T06.13** Add scope regression tests for implementation-only and artifact/adapter-only changes.
- [x] **T06.14** Add a narrow ignore exception for approved forecast Parquet artifacts while preserving unrelated ignore rules.
- [ ] **T06.15** Review `docs/ci.md` and run the updated setup/check path on a clean environment.

**Completion evidence:** package import, test discovery, type checking and scope-selection checks pass.

## T07. Normalize and validate input records

**Depends on:** T02, T03, T06. **Deliverable:** pure parsers and validation reports. **Owner:** data implementation agent.

- [ ] **T07.01** Implement source-file hashing and provenance attachment.
- [ ] **T07.02** Implement canonical crop-alias resolution with ambiguous-alias failures.
- [ ] **T07.03** Parse dates and availability metadata into the agreed types.
- [ ] **T07.04** Parse market observations without silently changing the market or price basis.
- [ ] **T07.05** Implement documented tonne/kg/package conversions.
- [ ] **T07.06** Implement daily-to-monthly aggregation only for the accepted source contract, excluding repeated cumulative totals.
- [ ] **T07.07** Parse calendar windows, duration ranges and guideline yield ranges.
- [ ] **T07.08** Parse cost subtotals, budget dates, region and VAT metadata.
- [ ] **T07.09** Validate required fields, finite values and allowed ranges.
- [ ] **T07.10** Detect identical duplicates separately from conflicting natural-key duplicates.
- [ ] **T07.11** Emit deterministic canonical rows and actionable row/field validation errors.
- [ ] **T07.12** Test source-shaped fixtures, conversions, invalid aliases, malformed records and deterministic normalization.

**Completion evidence:** pure parsers pass their tests without database imports or connections.

## T08. Add CPI data and conversion functions

**Depends on:** T02, T04, T06. **Deliverable:** CPI snapshot, provenance and tested conversions. **Owner:** data agent; lead reviews invariance.

- [ ] **T08.01** Retrieve the selected CPI level-index file from the verified source.
- [x] **T08.02** Confirm the series measures index levels rather than inflation percentages.
- [ ] **T08.03** Verify historical coverage and every observation required for the 2025 reporting base.
- [ ] **T08.04** Reconcile source index bases and revisions; reject unvalidated series splicing.
- [x] **T08.05** Write canonical `ml/data/cpi_za_monthly.csv` with deterministic ordering.
- [x] **T08.06** Record source URL, retrieval date, vintage, index definition and hashes in `SOURCES.md`.
- [ ] **T08.07** Implement the protocol's reporting-base calculation.
- [ ] **T08.08** Implement nominal-to-2025 reporting conversion and budget-date handling.
- [ ] **T08.09** Implement only the agreed cutoff-safe decision transformation from T04.
- [ ] **T08.10** Add `test_cpi_adjustment` using known observations from the committed snapshot.
- [ ] **T08.11** Test missing CPI, nonpositive indices and accidental repeated adjustment.
- [ ] **T08.12** Test future-CPI mutation against the decision contract, separately from reporting changes.

**Completion evidence:** committed source-traceable CPI and passing conversion/invariance tests.

## T09. Implement ORM reference-data imports

**Depends on:** T01, T03, T07. **Deliverable:** transactional backend commands. **Owner:** backend agent.

- [ ] **T09.01** Map canonical records onto the reconciled #8 ORM models.
- [ ] **T09.02** Add only missing model fields and declared database constraints.
- [ ] **T09.03** Create the required additive migration without handwritten SQL.
- [ ] **T09.04** Preserve vision migration/ORM parity checks and add reference-schema tests.
- [ ] **T09.05** Add the market-price import entry point to the selected command surface.
- [ ] **T09.06** Add the crop-calendar import entry point.
- [ ] **T09.07** Add the crop-cost import entry point.
- [ ] **T09.08** Validate complete input files before opening the write phase.
- [ ] **T09.09** Persist data and successful import metadata in one ORM transaction.
- [ ] **T09.10** Implement the identical-source/hash/parser-version no-op policy.
- [ ] **T09.11** Implement explicit changed-source conflicts and concurrent retry handling.
- [ ] **T09.12** Test repeated imports, partial-failure rollback and natural-key uniqueness with the supported database fixture.
- [ ] **T09.13** Run `test_import_idempotent`, migration safety, schema checks and the no-raw-SQL guard.

**Completion evidence:** repeated imports do not duplicate records and failed imports leave no partial writes.

## T10. Implement simple price forecasters

**Depends on:** T04, T06, T07, T08. **Deliverable:** historical quantiles and seasonal baseline. **Owner:** forecasting agent.

- [x] **T10.01** Implement a shared strict availability-cutoff filter.
- [ ] **T10.02** Select the crop/month training sample according to the fixed lookback policy.
- [ ] **T10.03** Convert eligible observations using the agreed prediction price basis.
- [x] **T10.04** Compute historical P10, P50 and P90 with fixed interpolation.
- [ ] **T10.05** Enforce minimum history and emit the agreed unsupported status when insufficient.
- [x] **T10.06** Locate the previous year's matching target-month observation.
- [x] **T10.07** Reject that baseline observation when unavailable at the planting cutoff.
- [x] **T10.08** Return both methods through the shared forecast record contract.
- [ ] **T10.09** Test hand-calculated quantiles, year boundaries and insufficient histories.
- [ ] **T10.10** Add `test_no_lookahead_forecast` cases that mutate post-cutoff values and availability metadata.

**Completion evidence:** exact fixture outputs and passing cutoff-invariance tests.

## T11. Implement LightGBM quantile forecasts

**Depends on:** T10. **Deliverable:** deterministic challenger model. **Owner:** forecasting agent.

- [ ] **T11.01** Implement target-month and forecast-horizon features.
- [ ] **T11.02** Implement lagged prices and historical summaries using only eligible observations.
- [ ] **T11.03** Fit any learned preprocessing separately inside each training window.
- [ ] **T11.04** Validate training labels against their own availability cutoffs.
- [ ] **T11.05** Implement the P10 quantile objective with frozen parameters.
- [ ] **T11.06** Reuse the same training path for P50 and P90 objectives.
- [ ] **T11.07** Apply pinned seeds, CPU/thread settings and supported deterministic options.
- [ ] **T11.08** Apply the fixed quantile-crossing correction through one shared prediction function.
- [ ] **T11.09** Return ordered quantiles and method/configuration metadata in the common contract.
- [ ] **T11.10** Test feature cutoffs, unavailable labels, missing history and repeated predictions.

**Completion evidence:** all challenger training inputs satisfy cutoffs and outputs pass the shared forecast tests.

## T12. Evaluate forecasts and select methods over time

**Depends on:** T10, T11. **Deliverable:** temporal forecast ledger and evaluation JSON. **Owner:** forecasting agent; lead reviews temporal logic.

- [ ] **T12.01** Enumerate validation origins and harvest horizons from the protocol.
- [ ] **T12.02** Reconstruct each validation training set at that origin's own cutoff.
- [ ] **T12.03** Generate validation forecasts from each method without later-origin training data.
- [ ] **T12.04** Define common target IDs and record missing/failed predictions for every method.
- [ ] **T12.05** Compute the fixed quantile loss and diagnostic median error/interval coverage.
- [ ] **T12.06** Filter validation outcomes to those available before each selection cutoff.
- [ ] **T12.07** Select the winning method using the fixed aggregation and tie rules.
- [ ] **T12.08** Store target IDs, counts, losses, selection cutoff and selected method in the ledger.
- [ ] **T12.09** Generate `forecast_backtest.json` from the ledger.
- [ ] **T12.10** Add `test_method_selection_picks_backtest_winner` with controlled winners and ties.
- [ ] **T12.11** Test that future outcomes cannot alter earlier method choices.
- [ ] **T12.12** Test that an all-period model or a method's silently reduced target set cannot pass temporal evaluation.

**Completion evidence:** independently reconstructable method choices and passing leakage tests.

## T13. Build recommendations and the decision ledger

**Depends on:** T04, T07, T08, T12. **Deliverable:** synthetic-tested decision engine. **Owner:** backtest agent.

- [ ] **T13.01** Enumerate the 156 planting months from January 2012 through December 2024.
- [ ] **T13.02** Derive each month's in-season candidate crops from the frozen calendar.
- [ ] **T13.03** Derive each crop's harvest month and occupied duration using the fixed timing rule.
- [ ] **T13.04** Attach cutoff-safe forecasts and record missing-candidate failures.
- [ ] **T13.05** Implement the shared gross-margin function with explicit units.
- [ ] **T13.06** Calculate each candidate's predicted margin from P50 and agreed yield/cost assumptions.
- [ ] **T13.07** Select and freeze the highest-margin recommendation with deterministic tie-breaking.
- [ ] **T13.08** Expand the recommendation into one comparison for each eligible default crop.
- [ ] **T13.09** Label no-switch and switch decisions before reading actual outcomes.
- [ ] **T13.10** Attach each crop's realized harvest-month price only in the scoring stage.
- [ ] **T13.11** Record unscorable outcomes without changing the frozen recommendation.
- [ ] **T13.12** Compute actual margins and rand gains and record all ledger/skip fields.
- [ ] **T13.13** Add `test_gross_margin_formula` for units, duration differences and negative margins.
- [ ] **T13.14** Add `test_no_lookahead_recommendation`, ties and late-2024 harvest cases.

**Completion evidence:** synthetic ledger rows match manual calculations and future outcomes change scoring only.

## T14. Calculate metrics and bootstrap intervals

**Depends on:** T13. **Deliverable:** validated crop and pooled statistics. **Owner:** statistics implementation agent.

- [ ] **T14.01** Count eligible/skipped months and eligible/scorable default rows separately.
- [ ] **T14.02** Count switches, no-switches, wins, losses and ties using fixed tolerances.
- [ ] **T14.03** Compute switch rate and switch-win rate with explicit denominators.
- [ ] **T14.04** Compute median rand gain including losses and ties.
- [ ] **T14.05** Compute per-switch percentage gains only where the protocol defines them.
- [ ] **T14.06** Store percentage-eligible and percentage-excluded counts.
- [ ] **T14.07** Compute p10 and worst loss using the fixed interpolation/sign conventions.
- [ ] **T14.08** Implement bootstrap sampling that preserves the chosen dependent groups.
- [ ] **T14.09** Apply deterministic seeding and the fixed replicate count.
- [ ] **T14.10** Handle zero-switch replicates and insufficient valid resamples explicitly.
- [ ] **T14.11** Calculate `median_gain_ci90` using the agreed shape and percentile rule.
- [ ] **T14.12** Recompute pooled statistics from all ledger rows instead of averaging crop summaries.
- [ ] **T14.13** Implement only sensitivity checks preregistered in T04.
- [ ] **T14.14** Test manual results, uneven crop counts, no switches and nonpositive default margins.
- [ ] **T14.15** Test bootstrap group preservation, reproducibility and undefined intervals.

**Completion evidence:** eight crop entries plus pooled, complete required fields and reconstructable denominators.

## T15. Generate JSON, the table and slide text

**Depends on:** T14. **Deliverable:** reports derived from one statistics object. **Owner:** reporting agent.

- [ ] **T15.01** Build the shared report object with exactly the eight included defaults and pooled.
- [ ] **T15.02** Attach input hashes, protocol identity and run metadata.
- [ ] **T15.03** Attach beetroot/pumpkin exclusions and processing-tomato/source caveats automatically.
- [ ] **T15.04** Serialize `decision_backtest.json` using the agreed schema.
- [ ] **T15.05** Generate an alphabetical crop table and separate pooled row in `decision_backtest.md`.
- [ ] **T15.06** Implement one shared numerical display/rounding function.
- [ ] **T15.07** Map sentence N, X and Y to pooled decisions, win rate and median rand gain.
- [ ] **T15.08** Map A and B to the minimum/maximum defined default switch-win rates under the protocol's completeness rule.
- [ ] **T15.09** Render the exact sentence template or the preregistered insufficient-evidence status.
- [ ] **T15.10** Add `test_table_lists_every_default` and JSON contract checks.
- [ ] **T15.11** Add `test_slide_sentence_from_results`, including rounding and undefined-statistic cases.

**Completion evidence:** table and sentence numbers match the JSON source; no manually entered headline figures.

## T16. Export the #21 deployment snapshot

**Depends on:** T03, T12. **Deliverable:** `forecasts.parquet` and its validator. **Owner:** forecast integration agent.

- [ ] **T16.01** Select the final snapshot's recorded training/as-of cutoff.
- [ ] **T16.02** Enumerate every required crop and all 12 consumer month keys.
- [ ] **T16.03** Produce predictions at that cutoff using the agreed selection policy.
- [ ] **T16.04** Attach method, price basis, currency, units and schema metadata.
- [ ] **T16.05** Keep the snapshot distinct from historical forecast ledger rows.
- [ ] **T16.06** Write the agreed Parquet column types and key ordering.
- [ ] **T16.07** Implement validation for exact grid completeness and unique keys.
- [ ] **T16.08** Implement finite positive-price and ordered-quantile validation.
- [ ] **T16.09** Implement metadata, schema-version and currency/unit validation.
- [ ] **T16.10** Expose `python ml/forecast/validate_output.py <path>` with actionable failures.
- [ ] **T16.11** Test missing months, duplicates, zero/negative prices and crossed quantiles.
- [ ] **T16.12** Test that historical ledger files cannot validate as deployment snapshots.
- [ ] **T16.13** Document the handoff to #21, leaving activation, rollback and the active-run 50% P50 guard with that issue.

**Completion evidence:** a valid consumer fixture and generated snapshot pass the same validator.

## T17. Make output files byte-reproducible

**Depends on:** T12, T15, T16. **Deliverable:** deterministic artifacts and manifests. **Owner:** reproducibility agent.

- [ ] **T17.01** Define canonical hashing inputs for data, configuration, code and protocol.
- [ ] **T17.02** Implement deterministic run ID generation from those inputs.
- [ ] **T17.03** Fix JSON key order, missing values and numeric serialization.
- [ ] **T17.04** Fix ledger row ordering and tie-order behavior.
- [ ] **T17.05** Pin Parquet writer version, compression and relevant serialization settings.
- [ ] **T17.06** Remove volatile execution timestamps and machine paths from deterministic files.
- [ ] **T17.07** Record stable environment/runtime metadata and tested platform bounds.
- [ ] **T17.08** Run the complete synthetic pipeline in two separate clean output locations.
- [ ] **T17.09** Compare hashes and bytes for every required artifact, report and manifest.
- [ ] **T17.10** Add `test_reproducible_output` around independent pipeline executions.
- [ ] **T17.11** Verify meaningful input/configuration changes produce a different run identity.

**Completion evidence:** byte comparisons pass within the documented supported environment.

## T18. Build the credential-free Colab workflow

**Depends on:** T05–T08 and T12–T17. **Deliverable:** verified notebook and run instructions. **Owner:** notebook/integration agent.

- [ ] **T18.01** Create `ml/notebooks/forecast_and_backtest.ipynb` with a documented execution order.
- [ ] **T18.02** Add checkout/setup cells pinned to an explicit code revision.
- [ ] **T18.03** Install the exact offline dependency set without backend initialization.
- [ ] **T18.04** Add input retrieval/loading and source-hash validation cells.
- [ ] **T18.05** Add runtime checks for the required Python/library versions.
- [ ] **T18.06** Add protocol-content and main-history verification before real decision execution.
- [ ] **T18.07** Run synthetic acceptance tests through shared commands rather than copied notebook logic.
- [ ] **T18.08** Invoke forecast generation and snapshot validation through package entry points.
- [ ] **T18.09** Invoke the real decision engine only after the merged-protocol gate succeeds.
- [ ] **T18.10** Package manifests, ledgers, forecasts and reports for a later results PR.
- [ ] **T18.11** Verify a fresh credential-free runtime can complete the synthetic workflow.
- [ ] **T18.12** Test refusal of missing history, mismatched protocol and incorrect input hashes.
- [ ] **T18.13** Clear stored notebook outputs and inspect for credentials/private inputs.
- [ ] **T18.14** Run the issue's directory secret scan and the repository's pinned full-history Gitleaks equivalent.
- [ ] **T18.15** Document supported execution, expected outputs and failure recovery without automatic publishing.

**Completion evidence:** clean synthetic notebook execution plus tested real-run refusal conditions.

## T19. Execute and publish the registered experiment

**Depends on:** all earlier tasks. **Deliverable:** reviewed real results and acceptance evidence. **Owner:** lead with independent result review.

- [ ] **T19.01** Record the merged protocol version, code revision and complete input hashes for the real run.
- [ ] **T19.02** Confirm all prerequisite tests and protocol execution gates pass.
- [ ] **T19.03** Execute the registered forecast and decision workflow in the pinned Colab environment.
- [ ] **T19.04** Repeat the run under the same supported conditions and compare all output bytes.
- [ ] **T19.05** Validate the real deployment snapshot with the acceptance CLI.
- [ ] **T19.06** Review forecast losses and selected methods for every crop.
- [ ] **T19.07** Review eligibility, missing outcomes and late-2024 harvest coverage.
- [ ] **T19.08** Review every default's gains, losses, denominators and uncertainty without suppressing weak results.
- [ ] **T19.09** Verify the generated sentence against JSON and confirm its claims match the registered experiment.
- [ ] **T19.10** Run `make lint`, `make typecheck` and `make test`.
- [ ] **T19.11** Run `pytest ml/forecast ml/backtest` and retain the named acceptance-test results.
- [ ] **T19.12** Run import idempotency/integration checks and required secret scans.
- [ ] **T19.13** Verify required Parquet/report files are actually tracked and prepare the results PR.
- [ ] **T19.14** Attach manifests, ledgers, caveats and test evidence to the results PR.
- [ ] **T19.15** After results merge, verify final mainline protocol-before-results ordering.
- [ ] **T19.16** Provide #21 with the validated snapshot, schema and price-basis documentation.
- [ ] **T19.17** Map every issue acceptance criterion to concrete evidence and list any remaining failure before issue closure.

**Completion evidence:** real results delivered through the required PR workflow, with every acceptance criterion evidenced or explicitly unmet.

## Progress and assignment

Use this compact record when assigning a group of subtasks:

| Field        | What to record                                  |
| ------------ | ----------------------------------------------- |
| Subtask IDs  | Exact IDs from this checklist                   |
| Owner        | Person or agent responsible                     |
| Dependencies | Required completed IDs or decisions             |
| Files        | Module/configuration paths the owner may change |
| Evidence     | Test output, artifact path or review/PR link    |
| State        | Open, in progress, blocked, or complete         |

Assign source inspection, parsers, report generation and bounded synthetic tests to lower-cost agents where useful. Keep CPI/scenario decisions, schema reconciliation, shared-contract edits and final acceptance review with the lead. Avoid simultaneous edits to the same configuration or model files.
