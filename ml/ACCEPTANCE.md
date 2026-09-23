# Issue #20 acceptance evidence

Updated 2026-09-23. This is implementation evidence for the senior-review
follow-up, **not a completed issue**. No real decision backtest was executed.

## Verified locally

### Senior-review follow-up

- Report schema 2 rejects incomplete historical grids before calculating metrics
  and derives displayed month bounds from validated coverage. All six R01 items
  are covered by regression tests, including missing interior months/defaults,
  out-of-period rows, duplicates, explicit skips and synthetic relabelling.
- `uv run pytest ml/forecast ml/backtest scripts/tests/test_audit_issue20_market_workbooks.py -q`:
  **97 passed** (93 ML tests and 4 source-audit tests).
- Full `uv run pytest -q`: **928 passed, 15 skipped, 33 deselected**. Skips require
  `jq`; integration tests remain deselected. Repository Ruff and changed-file
  formatting checks pass. ML implementation (16 files) and audit-script mypy pass.
  Gitleaks directory scans of `ml/` and the ML implementation report no leaks.
  Required `gitleaks detect --source ml/ --config .gitleaks.toml --redact` also
  exits 0 (115 commits). `check_protocol_first.py --check-ready` correctly exits 1:
  `ml/backtest/PROTOCOL.md` is absent from local `origin/main` history.
- Original Department workbooks for 2008–2024 were hashed and audited: eight
  crops × twelve monthly Joburg prices in every year. Release dates/revision
  histories and post-2024 harvest prices remain unverified. See the source audit.
- Eight modern budget PDFs and an older cabbage version were hashed and inspected.
  Budget/calendars review remains incomplete; these are not historical input approvals.
- The user-selected strict historical-input policy is recorded in
  `backtest/INFORMATION_POLICY.md`, with the CPI ranking counterexample and tests
  for future costs and post-decision reporting conversions. Source-specific lag,
  vintage loading and integrated mutation testing remain open.

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

The follow-up confirms monthly Johannesburg workbook contents; historical
availability metadata is still missing. Modern budget fields have been extracted,
but historical cost releases and calendar/component assumptions remain unresolved.
The user selected strict historical inputs. The real decision backtest remains
blocked by those sources and separate protocol registration.

## Dependencies and next work

Remote main was inspected read-only at
`1cc591bcc7966ac46ee77572ce949d8385945621`, newer than the current checkout's
`ed69b882af4043af2b1d32894ba5f32b56dcd5a2`. It includes migrations through `0007`
and #21's normalized fixture contract. Preserve local work while reconciling that
base before adding reference migrations. No remote changes were made here.

The snapshot exporter follows that contract: eight crops × twelve planting-month
numbers, integer growing months, decimal(14,4) amounts, 2025 ZAR/kg, explicit
as-of, source hashes and data-kind labels. `consumer_json` emits its Decimal strings.
Full consumer validation on the merged branch remains to run.

Resolve the **historical information versus fixed 2025-cost scenario** first:
`backtest/PROTOCOL_DRAFT.md` provides concrete proposed settings and required
decisions. Verify historical Joburg price coverage, source calendars and budget
subtotals; complete imports; finalize and merge the protocol separately; then
integrate the gated real runner, Colab notebook and actual result artifacts.

Native Make is unavailable and Node dependencies remain absent after the earlier
installation request was declined. No successful complete `make lint/typecheck/test`
run is claimed. Pinned ML runtime tested here: Python 3.12.11, LightGBM 4.7.0,
NumPy 2.5.3, PyArrow 25.0.1 on Windows. Other platforms/Colab remain unverified.
