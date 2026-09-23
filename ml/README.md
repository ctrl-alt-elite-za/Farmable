# Offline reference-data foundation

Issue #20's implementation provides an installable `farmable_ml` package,
canonical price validation, explicit-unit money calculations, cutoff-aware simple
and LightGBM forecasts, temporal method selection, decision scoring, report generation,
Parquet validation, a staged-data inventory and a protocol-history checker. The package
lives in `apps/ml-service/src/farmable_ml`; public checks and artifacts use `ml/`.

These components are exercised on synthetic fixtures. No real decision simulation,
production forecast snapshot or approved protocol is included yet. NumPy, PyArrow
and LightGBM are pinned in the package manifest and workspace lockfile. Reporting
CPI data and extraction provenance are in `ml/data/SOURCES.md`. Proposed statistical
settings and unresolved decisions are in `ml/backtest/PROTOCOL_DRAFT.md`.

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

The protocol checker currently fails because `ml/backtest/PROTOCOL.md` has not been
merged on main. This is intentional. Preparation mode requires the local protocol to
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

`observations_before(records, cutoff)` uses strict `available_on < cutoff`, where the
cutoff is the first day of planting month. It filters only; it neither imputes missing
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

1. Verify sufficient monthly Joburg history; staged FAOSTAT data is a different
   price source and the combined pumpkin/butternut series remains unresolved.
2. Verify source calendars, budget subtotals and the CPI transcription against the original PDF.
3. Resolve fixed modern budgets versus the literal planting-time-information claim.
4. Freeze and separately merge the protocol before real decision evaluation.
5. Integrate the tested components into a gated real-data runner, implement ORM
   reference imports on the current mainline schema, and verify the Colab workflow.

## Acceptance evidence boundaries

`test_no_lookahead_forecast`, `test_no_lookahead_recommendation`,
`test_method_selection_picks_backtest_winner`, `test_gross_margin_formula`,
`test_table_lists_every_default`, and `test_slide_sentence_from_results` exercise
the corresponding implementation on synthetic fixtures. The LightGBM test actually
fits three quantile models and checks repeatability and future-price mutation.

`test_reproducible_output` compares report/manifest bytes from separate Python
processes with different input orders and hash seeds. Parquet byte stability is
also tested, but a complete real forecast/backtest run is still required before
claiming end-to-end artifact reproducibility. The writer for development reports
accepts only synthetic inputs.

`python ml/forecast/validate_output.py <file>` validates the actual Parquet schema,
96 crop/planting-month keys, decimal precision, ordered positive prices and metadata.
The `consumer_json` adapter matches #21's normalized fixture contract as inspected
at remote main `1cc591bcc7966ac46ee77572ce949d8385945621`. Its production importer
must still be tested against the exported real artifact after branch integration.

This foundation adds no database connection, scheduled job, credential requirement
or automatic publication step.
