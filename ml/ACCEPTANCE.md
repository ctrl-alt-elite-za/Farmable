# Issue #20 acceptance evidence

Updated 2026-09-23. This is implementation evidence for the senior-review
follow-up and retrospective-scenario registration, **not a completed issue**. No
real decision backtest was executed.

The project owner selected the retrospective fixed-2025-input scenario so code and
artifacts can be completed before historical data cleanup. `backtest/PROTOCOL.md`
freezes the current-vintage price, CPI, cost, calendar and reporting rules and
prohibits the historical publication-availability claim.

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
