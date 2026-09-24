# Issue #20 acceptance evidence

Updated 2026-09-24. This is implementation evidence for the senior-review
follow-up and retrospective-scenario registration, **not a completed issue**. No
real decision backtest was executed.

The project owner selected the retrospective fixed-2025-input scenario so code and
artifacts can be completed before historical data cleanup. `backtest/PROTOCOL.md`
freezes the current-vintage price, CPI, cost, calendar and reporting rules and
prohibits the historical publication-availability claim.

## 24 September follow-up: integrated retrospective simulation

PR #77 has now merged on `main` at `73e2c6296a5a`. The preparation check passes
against freshly fetched `origin/main`; the working protocol byte-matches the
registered SHA-256 `a090d4e9d517b2b8c0d9d5009b5b9c5c9a827386e178f6e265052270923ea99d`.
No real decision experiment has been executed by this follow-up.

- `ObservationPolicy.RETROSPECTIVE` makes a monthly observation eligible on the
  first day of the next month. Historical ranges, the diagnostic baseline,
  LightGBM features/labels and every validation fold share this explicit policy.
  Existing callers still default to strict publication availability, and source
  timestamps are not rewritten.
- `farmable_ml.retrospective` integrates constant-2025 price normalization,
  per-crop/horizon method selection, the registered frozen production assumptions,
  marketing deductions, recommendation freezing and subsequent outcome scoring.
  Assumption tables are checked against the actual registered protocol in tests.
- All 1,248 audit-grid keys remain present. Missing forecasts, seasonality and
  unavailable realized prices are skips, never zero-profit substitutes. Post-2024
  prices remain excluded from scoring even if supplied. Negative margins and
  alphabetical exact ties are retained.
- A per-simulation predictor cache reuses identical historical fits without
  sharing predictions across datasets. Failed method selections retain their
  evaluated folds and per-method losses instead of losing the audit evidence.
- Verification: **146 tests passed** across `ml/forecast`, `ml/backtest`, market
  workbook-audit tests and source-manifest tests. This includes 16 new tests,
  real pinned LightGBM fits on fabricated observations, an integrated real-model
  walk-forward selection, future-price mutation, preserved strict-mode behavior,
  input-order reproducibility, Decimal-context isolation and full-grid synthetic
  report comparison. Changed Python Ruff/format and targeted mypy checks pass.

The simulation core is not the real-data publication entry point. Canonical
source loading with hash verification, ORM reference imports, the gated CLI and
Colab workflow, full artifact/manifest export and two independent real runs are
still required. No real result files, deployed models or forecast snapshot were
generated, and #20 remains incomplete. The latest checks above supersede the
pre-merge protocol status in the earlier checkpoint below.

## 24 September follow-up: retrospective report support

The registered scenario and the implementation were inconsistent: `build_report`
only accepted strict historical availability, and the sentence renderer always
used the old planting-time-publication claim. Report schema 3 now carries an
explicit scenario separately from synthetic/real-observation provenance.

- `retrospective_fixed_2025` uses the registered sentence and required caveats.
  Real-observation reports require observation-cutoff attestation, never a false
  claim that current-vintage inputs were published at the old planting origin.
- The existing strict mode, complete-grid validation, losses, skips, denominators
  and bootstrap calculations are preserved. Synthetic warnings are retained,
  including insufficient-evidence output. The development writer still refuses
  every real-observation report and validates before creating output directories.
- Regression tests use fabricated ledgers only. They check both rendering paths,
  altered policy metadata, missing coverage, required caveats, deterministic
  synthetic artifacts and the real-publication restriction.

This removes a reporting integration blocker, **not** the remaining execution
work. No real forecast/backtest or Colab execution has occurred. The protocol gate
still rejects the actual `origin/main` because #77 has not merged there. #73 merged
into the foundation branch, which does not satisfy that gate.

At that reporting-only checkpoint, the remaining work was:

- Implement the registered next-month observation eligibility in the runner:
  the existing strict `observations_before` helper uses `< cutoff`, while version 1
  permits an observation on its next-month analytical eligibility date. Keep the
  strict mode intact rather than forging historical release dates.
- Wire constant-2025 price conversion and frozen modern costs/calendars into
  recommendations; existing `Candidate` requires costs available before planting.
  Apply the registered marketing deductions consistently in predictions and scores.
- Complete the protocol-gated runner, canonical reference imports and Colab
  workflow before running/publishing real artifacts. The report's caller
  attestation does not implement or independently verify those requirements.

That checkpoint changed only reporting, its tests and these handoff notes. No input
values, protocol rules, trained model parameters, UI, database schema or CI gates
were changed.

Verification on the isolated follow-up branch:

- `pytest ml/backtest/test_reports.py ml/backtest/test_retrospective_reports.py ml/backtest/test_decision.py -q`:
  **57 passed** (the original report/decision baseline was 34 passing tests).
- `pytest ml/forecast ml/backtest scripts/tests/test_audit_issue20_market_workbooks.py scripts/tests/test_issue20_source_manifests.py -q`:
  **130 passed**, with one Windows pytest-cache permission warning; no test skips.
  This includes real LightGBM fits on synthetic data and temporary-Git-repository
  protocol tests. Pinned ML dependencies match `uv.lock` (LightGBM 4.7.0, NumPy
  2.5.3, PyArrow 25.0.1, SciPy 1.18.1, Narwhals 2.26.0), on Python 3.12.14.
- Changed Python Ruff/format checks and `mypy -p farmable_ml.reports` passed.
- Actual preparation gate: expected failure, `protocol is missing from mainline
  origin/main: ml/backtest/PROTOCOL.md`. No results were generated to bypass it.

These are component/integration tests for the offline ML package, not a claim
that the full application, hosted CI or a real-data experiment was executed.

## Verified locally

### Senior-review follow-up

- Report schema 2 rejects incomplete historical grids before calculating metrics
  and derives displayed month bounds from validated coverage. All six R01 items
  are covered by regression tests, including missing interior months/defaults,
  out-of-period rows, duplicates, explicit skips and synthetic relabelling.
- `uv run pytest ml/forecast ml/backtest scripts/tests/test_audit_issue20_market_workbooks.py scripts/tests/test_issue20_source_manifests.py -q`:
  **107 passed**.
- The non-shell repository suite passes: **813 passed, 33 deselected**. The four
  omitted test modules invoke Windows `bash.exe`; this machine currently has the
  WSL relay but no `/bin/bash`, so the unfiltered run stops on that environment
  error. Repository Ruff and changed-file formatting checks pass. ML
  implementation (17 files) and audit-script mypy pass.
  Gitleaks directory scans of `ml/` and the ML implementation report no leaks.
  Required `gitleaks detect --source ml/ --config .gitleaks.toml --redact` also
  exits 0 (115 commits). `check_protocol_first.py --check-ready` correctly exits 1:
  `ml/backtest/PROTOCOL.md` is absent from local `origin/main` history.
- Original Department workbooks for 2008–2024 were hashed and audited: eight
  crops × twelve monthly Joburg prices in every year. Matching official archive
  captures establish conservative availability bounds for 2008–2020; 2021–2024
  remain unknown. A separate official quarterly report was visually reviewed and
  supplies October 2024–March 2025 Johannesburg values for seven crops, with
  spinach absent. See the source audits.
- Eight modern budget PDFs and an older cabbage version were hashed and inspected.
  All requested source fields/subtotals and the experiment subtotal mapping are
  recorded; these are not historical input approvals. The official ARC calendar
  booklets are now hashed and reviewed, with page-level missing/ambiguous fields
  recorded rather than inferred.
- `backtest/INFORMATION_POLICY.md` preserves the deferred strict policy and records
  the selected retrospective fixed-input scenario. Existing cutoff, vintage and
  mutation tests remain as guardrails; version 1 instead uses an analytical
  next-month observation cutoff and must carry the retrospective caveat.

### Earlier foundation checks

- `uv run pytest ml/forecast ml/backtest -q`: **71 passed**.
- `uv run pytest ml/forecast ml/backtest scripts/tests apps/backend -q`:
  **902 passed, 15 skipped, 33 deselected**. The skips require `jq`; deselected
  integration tests require the disposable PostgreSQL/Docker stack.
- Repository Ruff check passed. Changed Python formatting check passed (23 files).
- mypy passed for backend/scripts/migrations/E2E/root fixture (117 files),
  ML/vision implementation (16 files) and ML adapters/tests (11 files).
  ML implementation checking uses `MYPYPATH=src` inside `apps/ml-service` to avoid
  confusing its source layout with the existing vision package namespace.
- No-raw-SQL guard passed across 91 backend/migration files.
- Official Gitleaks **8.21.2** native binary was downloaded into ignored `.ci-tmp`,
  and its ZIP verified against the release's published SHA-256 checksum.
  `detect --source ml/ --config .gitleaks.toml --redact` exited 0; directory scans
  of both `ml/` and `apps/ml-service/src/farmable_ml` also exited 0, covering new
  untracked files. Full available Git-history scan with `--log-opts=--all` exited
  0 (111 commits). Docker was stopped, so the workflow image itself was not run.
- `git diff --check` passed.

The previously failing photo runtime test now uses a temporary file-backed SQLite
database with separate connections for concurrent requests. Its former StaticPool
shared one DBAPI connection across concurrent sessions. The fixture change applies
only to the explicitly parametrized concurrency test; production code is unchanged.

## Acceptance mapping

| Required evidence                                | Current evidence                                                                                 | Still needed                                                                               |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------ |
| `test_no_lookahead_forecast`                     | Simple forecast future-price mutation passes; separate real LightGBM fit/mutation test passes    | Agreed inflation-adjusted prediction basis and end-to-end CPI/vintage invariance           |
| `test_no_lookahead_recommendation`               | Synthetic cutoff-aware forecasts/costs and frozen recommendation pass                            | Integrated method selection/calendar/CPI policy on audited inputs                          |
| `test_method_selection_picks_backtest_winner`    | Controlled temporal winners, changing winners over time and common-target failure tests pass     | Multi-horizon aggregation, diagnostic baseline and forecast evaluation artifact            |
| `test_reproducible_output`                       | Separate-process report/manifest byte equality passes; Parquet order stability also passes       | Complete independent real-run equality, code/protocol/input/config run identity            |
| `test_cpi_adjustment`                            | On-disk Stats SA 2012 observation and full 2025 base conversion pass                             | Commit reviewed data; independent original-PDF transcription check; historical cost policy |
| `test_gross_margin_formula`                      | Explicit-unit, loss and duration arithmetic passes                                               | Real scenario inputs and approved money basis                                              |
| Protocol history exits 0                         | Merge/squash/order fixtures pass; actual checker correctly rejects missing protocol              | Finalized separate protocol PR merged before execution/results                             |
| JSON eight crops + pooled, fields and exclusions | Synthetic generated report shape and null/denominator tests pass                                 | Real validated report and full source manifest                                             |
| Every-default table                              | `test_table_lists_every_default` passes                                                          | Real artifact                                                                              |
| Generated slide sentence                         | `test_slide_sentence_from_results` passes, synthetic warning retained                            | Real artifact with evidence supporting the exact wording                                   |
| Parquet validator exits 0                        | CLI actually exits 0 against temporary 96-row Parquet fixture; rejects invalid grid/prices/basis | Real `results/<run_id>/forecasts.parquet` and consumer integration                         |
| `test_import_idempotent`                         | Not implemented for #20 reference imports                                                        | Current-main reconciliation, reference schema/migrations and ORM import commands/tests     |
| Gitleaks                                         | Local directory and available full-history scans passed                                          | Repeat in eventual PR CI with complete fetched history                                     |

The CPI snapshot is a current-vintage **reporting** series. Models currently work
in the caller-supplied consistent price basis and do not pretend their nominal
inputs have been converted to 2025 rand. Do not infer full no-look-ahead acceptance
from a synthetic price-only mutation test.

The follow-up confirms monthly Johannesburg workbook contents. Conservative
archive bounds are recorded for 2008–2020, while 2021–2024 publication timing and
post-2024 spinach remain data-cleanup gaps. Version 1 proceeds as an explicitly
retrospective current-vintage scenario with frozen assumptions. Its real decision
backtest remains blocked only by separate protocol registration and runner/import
implementation, not by the deferred source cleanup.

## Dependencies and next work

Remote main was inspected read-only at `f375c0a`. It includes migrations through
`0008_weather_climatology` and #21's normalized fixture contract. The current
Issue #8 domain schema has no reference crop, market, calendar, cost or import
tables; `data.ReferenceSnapshot` is a forecast payload contract rather than a
database model. `data/REFERENCE_SCHEMA_RECONCILIATION.md` records the additive
model plan and requires a future migration to revise `0008`. No remote changes
were made here.

The snapshot exporter follows that contract: eight crops × twelve planting-month
numbers, integer growing months, decimal(14,4) amounts, 2025 ZAR/kg, explicit
as-of, source hashes and data-kind labels. `consumer_json` emits its Decimal strings.
Full consumer validation on the merged branch remains to run.

Obtain 2021–2024 release evidence and the missing post-2024 spinach coverage,
resolve calendar fields and VAT basis, and then finalize and merge the protocol
separately.
After that gate, complete imports and integrate the real runner, Colab notebook
and result artifacts.

Native Make is unavailable and Node dependencies remain absent after the earlier
installation request was declined. No successful complete `make lint/typecheck/test`
run is claimed. Pinned ML runtime tested here: Python 3.12.11, LightGBM 4.7.0,
NumPy 2.5.3, PyArrow 25.0.1 on Windows. Other platforms/Colab remain unverified.
