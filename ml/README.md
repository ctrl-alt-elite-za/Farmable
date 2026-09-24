# Offline reference-data foundation

Issue #20's implementation provides an installable `farmable_ml` package,
canonical price validation, explicit-unit money calculations, cutoff-aware simple
and LightGBM forecasts, temporal method selection, decision scoring, report generation,
Parquet validation, a staged-data inventory and a protocol-history checker. The package
lives in `apps/ml-service/src/farmable_ml`; public checks and artifacts use `ml/`.

These components and the integrated retrospective runner are exercised on synthetic
fixtures. A reproducible real retrospective result and 96-row snapshot are now
included under `ml/backtest/results/` and `ml/forecast/results/`; see
`ml/RESULTS_REVIEW.md` before using any number. The registered retrospective
fixed-input rules in `ml/backtest/PROTOCOL.md`
merged independently in PR #77 before any result run. NumPy, PyArrow
and LightGBM are pinned in the package manifest and workspace lockfile. Reporting
CPI data and extraction provenance are in `ml/data/SOURCES.md`. Proposed statistical
settings and source caveats are in `ml/backtest/PROTOCOL.md`.

## Run the foundation checks

From the repository root after `uv sync`:

```bash
uv run pytest ml/forecast ml/backtest
uv run python scripts/inventory_issue20_data.py --ref origin/issue-20-reference-data
uv run python ml/backtest/check_protocol_first.py --check-ready
```

The inventory reads committed CSV blobs without checking out the data branch or
writing raw input files. It reports staged coverage, hashes and limitations; it does
not certify that the inputs satisfy the experiment.

The protocol checker now passes preparation mode against the merged mainline
protocol. Preparation mode requires the local protocol to
exactly match the merged mainline tip. Default mode also requires mainline results
whose first introduction is strictly later than the protocol. Use `--repo` and
`--main-ref` for a different repository or mainline reference. All tracked files in
`ml/backtest/results/`, even `.gitkeep`, count as results; leave that directory absent
until genuine results are ready. Git history establishes commit ordering, not proof
of when somebody executed an unrecorded experiment.

The root `make test` and changed-scope hooks now include ML tests. Follow the existing
WSL instructions for Make on Windows. The native equivalent of the focused suite is
`.venv/Scripts/python.exe -m pytest ml/forecast ml/backtest`.

## Canonical price input, version 1

`farmable_ml.data.read_prices(content: bytes)` accepts UTF-8 CSV with these exact
ordered columns:

```csv
crop,market,observation_month,available_on,price_rand_per_kg,source_sha256
```

- `crop` uses the eight issue crops; known spelling aliases normalize explicitly.
  Combined pumpkin/butternut and excluded crops fail instead of being relabelled.
- `market` is an explicit identifier. Producer-price and Joburg series stay distinct.
- `observation_month` is `YYYY-MM-01`. `available_on` is the date this exact vintage
  became available and must follow the finalized observation month. Adapters must
  not invent historical publication dates from a download or scrape timestamp.
- Prices are finite, strictly positive **nominal ZAR/kg**, parsed as `Decimal`.
  This schema is not the inflation-adjusted forecasting or #21 snapshot contract.
- `source_sha256` identifies the original source bytes. The returned `PriceInput`
  also hashes the exact canonical CSV bytes, including line endings.

The parser rejects duplicate crop/market/month records, even identical duplicates.
Resolve source corrections and alternative vintages explicitly before producing a
single-vintage file. Source hashes preserve provenance; without the referenced blob
they do not independently establish authenticity or availability.

`observations_before(records, cutoff)` defaults to strict `available_on < cutoff`.
The explicit retrospective policy instead includes observations from months before
the planting month without claiming publisher availability. It filters only; it neither imputes missing
data nor proves a model's full absence of look-ahead. Full model and recommendation
invariance tests remain required when those components exist.

## Arithmetic and information boundaries

`farmable_ml.money.gross_margin` calculates:

```text
(price_rand_per_kg * yield_kg_per_ha - cost_rand_per_ha) / occupied_months
```

All arguments are finite `Decimal` values; yield/duration must be positive and
price/cost nonnegative. Losses remain negative. The caller must establish a common
price/cost basis. Calculation uses a local decimal context to avoid inheriting a
caller's unrelated precision settings.

`reporting_value` multiplies a signed amount by `reporting_cpi / observation_cpi`.
It is a retrospective reporting primitive, not a historical cost/recommendation
policy. `test_cpi_adjustment` now uses the on-disk Stats SA monthly series through
2025; committing it and independently verifying the transcription remain release
steps. The ranking counterexample test demonstrates why converting
fixed 2025 budgets with future CPI cannot silently become the recommendation rule.

## Next dependencies

### Retrospective runner

`ml/backtest/run_retrospective.py` implements the registered scenario. It verifies
the protocol history gate before reading workbooks, checks each workbook's bytes,
hash, sheet and cell audit, and never connects to a database. Supply the original
workbooks in one directory using the filenames in the committed source audit:

```bash
uv run --with xlrd==2.0.2 --with openpyxl==3.1.5 python ml/backtest/run_retrospective.py --workbooks /path/to/workbooks
```

The separate protocol PR is merged on `main`; the runner still refuses an unmerged
or byte-mismatched protocol. Use only reviewed original workbooks for a real run. It
exports decision and forecast ledgers, forecast evaluation and selection folds,
the 96-row snapshot, every-default report, generated sentence and hash manifests.
The run identity includes implementation, protocol, input/configuration hashes and
runtime versions. For an independent repeat, pass `--output /path/to/second/ml`
and compare every artifact byte; existing run directories are never overwritten.

Analytical availability includes an observation from the first day of the next
month. Ordinary publication-vintage records retain the strict earlier-than-origin
cutoff. Future CPI revisions remain a disclosed retrospective assumption.

The snapshot uses 2025 planting months and history ending in December 2024. Under
protocol Amendment 1, its 96 rows use frozen pre-2025 historical ranges for the
harvest target calendar month. The decision simulation retains per-origin model
selection. The snapshot exports gross market prices and separate costs/yields;
decision scoring additionally deducts the registered marketing rates. Real-artifact
consumer import and Colab execution remain outstanding. ORM
models and a bounded explicit importer now cover market prices, crop calendars and
costs. Identical canonical bundles are no-ops; changed identities and invalid
bundles fail without partial rows. After migration, import one with
`python -m farmable_backend.reference_cli BUNDLE.json`. Migration `0017` now follows
main's `0016_assistant_usage`; apply it explicitly through the normal migration
command. Bundles require `source_file` and `source_sha256`; market rows require
`availability_kind` (`publication` or `analytical_next_month`). Analytical dates
must equal the following month's first day and must never be described as source
publication dates. Concurrent identical imports return one import and subsequent
no-ops; natural-key conflicts roll back the entire transaction.

The #21 consumer now accepts the approved `retrospective` snapshot only when
`FORECAST_DATA_MODE=retrospective` is explicitly selected. Outlook responses retain
the label and a retrospective warning; historical mode rejects these inputs.
The runner writes `forecast.json` alongside Parquet for the existing importer.
Synthetic integration tests validate the complete export against the consumer
contract. Real-artifact integration remains gated by protocol registration.

`ml/notebooks/forecast_and_backtest.ipynb` is the thin Colab entry point. It
requires an exact 40-character commit SHA, installs the locked project plus the
two pinned workbook readers, runs the shared ML tests and protocol gate, and calls
the same runner. It contains no source data, credentials, copied model logic or
saved outputs. A real Colab execution and cross-environment artifact comparison
still require the independently merged protocol and audited workbook files.

### Remaining issue work

1. Review the real artifacts, especially the zero-switch tomato default. The
   registered eight-default slide sentence remains unavailable.
2. Execute the notebook in Colab and compare its artifacts with the local run.
3. Validate and import the real retrospective snapshot into a disposable database.
4. Complete deferred historical-source and licence cleanup without weakening the
   registered retrospective caveats.
5. After the results PR merges, verify the default protocol history gate.

## Acceptance evidence boundaries

`test_no_lookahead_forecast`, `test_no_lookahead_recommendation`,
`test_method_selection_picks_backtest_winner`, `test_gross_margin_formula`,
`test_table_lists_every_default`, and `test_slide_sentence_from_results` exercise
the corresponding implementation on synthetic fixtures. The LightGBM test actually
fits three quantile models and checks repeatability and future-price mutation.

`test_reproducible_output` compares report/manifest bytes from separate Python
processes with different input orders and hash seeds. Parquet byte stability is
also tested, but a complete real forecast/backtest run is still required before
claiming end-to-end artifact reproducibility. Retrospective artifact writing is
reachable only through the protocol-gated runner.

`python ml/forecast/validate_output.py <file>` validates the actual Parquet schema,
96 crop/planting-month keys, decimal precision, ordered positive prices and metadata.
The `consumer_json` adapter matches #21's normalized fixture contract as inspected
at remote main `1cc591bcc7966ac46ee77572ce949d8385945621`. Its production importer
must still be tested against the exported real artifact after branch integration.

This foundation adds no database connection, scheduled job, credential requirement
or automatic publication step.
