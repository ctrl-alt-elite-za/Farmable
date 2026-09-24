# Issue #20 acceptance evidence

Updated 2026-09-24. This is implementation and real-run evidence for the
retrospective scenario, **not a completed issue**. The real result is reproducible,
but the registered eight-default slide sentence is withheld because tomatoes have
no scorable switches. See `RESULTS_REVIEW.md`.

### Real result after PR #83

Amendment 1 merged in PR #83. The protocol readiness gate passed on the resulting
`main`. All 17 original workbooks matched the committed hashes, and the runner
produced run `5310d438e67b5333c22786a9b727f8c78fda671314677af9f77c59d131bd952d`.
An independent repeat produced the same ID and byte-identical copies of all ten
artifact files. The 96-row Parquet snapshot passed its validator, and its JSON
counterpart passed the backend's retrospective consumer quality checks.

The 1,248-key decision ledger has 444 scorable rows, 326 switches and 316 positive
switch gains. Tomatoes have 42 scorable rows, all no-switch; their switch win rate
and gain statistics are correctly null. `slide_sentence.txt` therefore reports
`INSUFFICIENT EVIDENCE`. This result must not be converted into an eight-default
pitch claim. The real snapshot imports and serves an outlook in a disposable ORM
test database. Colab execution, reviewer inspection, deployment and the final
results-history gate remain open.

The sections below retain earlier implementation checkpoints as historical records.

### First real-input run after PR #82

All 17 original workbooks in local ignored storage match the committed byte hashes.
After PR #82 merged, the first registered runner execution stopped before writing
result files: a later 2025 deployment-snapshot forecast lacked the 2025 lag months
required by its selected LightGBM method. No decision scores were inspected. A
dated Amendment 1 in `backtest/PROTOCOL.md` defines that snapshot from frozen
pre-2025 seasonal ranges, leaving the historical decision simulation unchanged.
The amendment and code merged before the successful real run; its results belong in
a separate PR.

The project owner selected the retrospective fixed-2025-input scenario so code and
artifacts can be completed before historical data cleanup. `backtest/PROTOCOL.md`
freezes the current-vintage price, CPI, cost, calendar and reporting rules and
prohibits the historical publication-availability claim.

### Registered protocol and simulation integration (24 September 2026)

Protocol-only PR #77 merged on `main` at `73e2c6296a5a`. Its original protocol
has SHA-256 `a090d4e9d517b2b8c0d9d5009b5b9c5c9a827386e178f6e265052270923ea99d`.
The amendment later merged in PR #83. Kea's issue-20 follow-up
simulation core is integrated into the local runner for frozen recommendations and
decision scoring. The runner retains its audited workbook loader, ORM import work,
forecast evaluation, snapshot export and deterministic artifact packaging.

The combined forecast/backtest suite passes **153 tests**, including real LightGBM
fits on synthetic data and a runner repeat with byte-identical artifacts. Ruff lint,
Ruff formatting, ML package mypy and runner mypy pass. No real workbooks were run,
no real results were produced.
PostgreSQL integration, Colab execution, original workbook acquisition, independent
real-run repetition and artifact review remain open.

## Verified locally

### Mainline integration and reference persistence (24 September 2026)

Integrated main at `73e2c62` into the runner branch. Added migration
`0017_reference_data`, revising main's `0016_assistant_usage`; its four tables
match ORM-generated DDL. No application
database was migrated. Source filenames and hashes are retained, and market rows
explicitly distinguish analytical eligibility from actual publication dates.
SQLite coverage verifies concurrent identical imports, complete rollback on a
natural-key conflict, source provenance and analytical date validation.
PostgreSQL race and migration-round-trip tests are wired into
`scripts/test-integration.sh` but remain unexecuted because Docker is stopped.

The runner now also writes `forecast.json`. The backend accepts that export in
explicit `retrospective` mode, preserves its label and returns a retrospective
warning in outlooks. Historical mode rejects it. The generated API client was
regenerated from FastAPI. Synthetic runner-to-consumer contract and authenticated
outlook checks pass; no real forecast was imported or deployed.

Validation in this continuation:

- Backend/ML suite before the consumer addition: **941 passed, 51 deselected**.
- Follow-up forecast, runner and available script suite: **294 passed**.
- Repository Ruff passes; broad mypy passes for **172 source files**.
- Follow-up mypy passes for the five changed consumer/import/runner modules.
- Node lint and workspace type checks pass; geo tests: **120 passed**. These
  used the installed pnpm, which warns that `pnpm.overrides` is ignored; a pinned
  pnpm 9.15.9 CI run remains necessary.
- Raw-SQL guard passes across **134 files**. ML and backend working-tree
  Gitleaks scans pass.
- Native Make/Bash remains unavailable. The script run excluded the six modules
  that invoke Bash: await-device, CI, forecast-deployment, integration-runner,
  repo-hooks and staging-infrastructure. No complete `make` run is claimed.
- The protocol history gate now passes against freshly fetched `origin/main`.
  No real backtest was executed.

Before closure: produce and repeat the real artifacts; validate/import the real
snapshot; execute the Colab notebook;
run PostgreSQL integration and complete repository checks; merge results in a
later PR and pass the final history gate. The publisher request is follow-up
source cleanup, not a version-1 blocker. Earlier evidence below describes prior
milestones and may reference the previous migration numbering.

### Resumed retrospective runner implementation

The local runner now integrates audited workbook loading, fixed-2025 normalization,
temporal method selection, marketing deductions, frozen recommendations, explicit
skips, forecast/decision ledgers, snapshot export, reports and provenance manifests.
The history gate executes before any source loading. Analytical next-month
eligibility is explicit; ordinary publication-vintage checks remain strict.

Synthetic integration tests cover future-price mutation, missing candidates,
seasonality and late-harvest skips, full 1,248-key ledger coverage, the 96-row
snapshot, and identical bytes across two runs with reversed input order. These
integration tests substitute simple deterministic predictors and a 100-replicate
bootstrap; existing separate LightGBM tests exercise the actual fitted models.
They do not establish real-input, full-10,000-replicate or cross-platform
reproducibility. Workbook hash rejection and mixed success/failure Parquet columns
are tested separately.

- Current focused verification: backend **550 passed, 33 deselected**; ML and
  source-audit **122 passed**. Repository Ruff, broad mypy (102 files), focused
  import mypy, the 94-file raw-SQL guard, and working-tree secret scans pass.
  Node checks could not start because Corepack could not verify/fetch the pinned
  pnpm release in this environment. Bash-dependent tests remain unavailable because
  the Windows WSL relay has no `/bin/bash`.

The earlier checkpoint below predates PR #77: its protocol-gate blocker is resolved.
No real results were generated. ORM
reference models and transactional imports now have synthetic idempotency coverage,
but their `0009` migration must be generated only after rebasing onto main's `0008`.
The credential-free Colab notebook is committed and structurally tested, but Colab
execution, real-run comparison, consumer integration and
the separate protocol/results PR sequence remain outstanding. The evidence below
records earlier milestones rather than claiming those remaining criteria are met.

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
| `test_import_idempotent`                         | Three bundle kinds pass identical-import no-op, conflict and atomic-failure tests                | Rebase on current main; add/review `0009`; PostgreSQL migration/concurrency verification   |
| Gitleaks                                         | Local directory and available full-history scans passed                                          | Repeat in eventual PR CI with complete fetched history                                     |

The CPI snapshot is a current-vintage **reporting** series. Models currently work
in the caller-supplied consistent price basis and do not pretend their nominal
inputs have been converted to 2025 rand. Do not infer full no-look-ahead acceptance
from a synthetic price-only mutation test.

The follow-up confirms monthly Johannesburg workbook contents. Conservative
archive bounds are recorded for 2008–2020, while 2021–2024 publication timing and
post-2024 spinach remain data-cleanup gaps. Version 1 proceeds as an explicitly
retrospective current-vintage scenario with frozen assumptions. Its real decision
backtest remains blocked by separate protocol registration, mainline migration
integration and real execution, not by the deferred source cleanup.

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
After that gate, rebase the reference schema onto migration `0008`, add `0009`,
verify the notebook in Colab, and produce independently repeated result artifacts.

Native Make and a working WSL Bash are unavailable. No successful complete
`make lint/typecheck/test` run is claimed. Pinned ML runtime tested here: Python
3.12.11, LightGBM 4.7.0,
NumPy 2.5.3, PyArrow 25.0.1 on Windows. Other platforms/Colab remain unverified.
