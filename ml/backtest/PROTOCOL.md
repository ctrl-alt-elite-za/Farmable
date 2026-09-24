# Issue 20 registered protocol

**Registered scenario:** retrospective fixed-2025-input simulation

**Protocol version:** 1

**Registered:** 23 September 2026

**Results inspected before registration:** none

This protocol replaces the strict historical-vintage proposal after the project
owner chose to finish the reproducible evaluation before completing historical
source cleanup. It measures a retrospective decision rule on the current audited
price history with one frozen set of modern production assumptions. It does not
claim that every source value was published or known at the simulated planting
date.

No real decision result may be generated until this file has merged independently
on `main`. Any change after that merge is a dated protocol amendment and requires
results under both the registered and amended rules.

### Amendment 1 — 24 September 2026: frozen 2025 deployment snapshot

Original registered protocol SHA-256:
`a090d4e9d517b2b8c0d9d5009b5b9c5c9a827386e178f6e265052270923ea99d`.

The first real-input execution of the registered runner stopped before writing any
result files. Its 96-row deployment snapshot attempted to select a model at each
2025 planting month, although the registered market series ends in December 2024.
For later planting months, the LightGBM challenger can win validation but cannot
construct its required recent lags. No decision scores or incomplete outputs were
inspected before this amendment.

For the **deployment snapshot only**, use the historical-range P10/P50/P90 of the
harvest target's calendar month for all eight crops and all twelve 2025 planting
months. Its information cutoff is 1 January 2025, so every snapshot estimate uses
only the registered 2008–2024 observations, already converted to constant 2025
rand. Record `historical_range` as the method for each row. Do not fill missing
2025 lags, incorporate the incomplete Q1 2025 report, or change the historical
decision simulation, its per-origin method selection, scoring, or ledgers.

The original runner produced no complete result to report under the unamended
snapshot rule. The eventual result package must disclose this failed attempt and
distinguish these frozen deployment estimates from the decision backtest forecasts.

## Scope and coverage

- Audit grid: every first-of-month origin from January 2012 through December 2024
  and each of eight defaults: butternut, cabbage, carrots, green beans, onions,
  potatoes, spinach and tomatoes. The grid therefore contains 1,248 unique keys.
- Beetroot and pumpkins are excluded because no reviewed Elsenburg cost budget is
  available. Both exclusions and reasons appear in every report.
- A grid row may be explicitly skipped for seasonality, unavailable forecast, or
  missing realized harvest price. Skips remain in coverage and never become zero
  gains or fabricated decisions.
- Market: Johannesburg fresh-produce market only. FAOSTAT producer prices and the
  staged 2026 daily scrape are not substitutes.

## Registered source scenario

### Market prices

Use the audited current files in `ml/data/market_workbook_audit.json`. Each accepted
monthly cell is Johannesburg R/ton and must agree with sales value divided by
tonnes under the audit tolerance. Convert it to nominal R/kg by dividing by 1,000.

The workbooks are treated as a current-vintage retrospective series. For temporal
model construction, an observation becomes analytically eligible on the first day
of the following month. This rule prevents a target month from entering an earlier
forecast; it is not a claim about the publisher's actual release date. Later-dated
observations must not alter an already frozen forecast or recommendation.

The official Q1 2025 PDF remains a separately audited candidate source and is not
spliced into version 1 because it omits spinach. Harvest targets after December
2024 are therefore explicit `missing_realized_price` skips.

### CPI and monetary basis

Use `ml/data/cpi_za_monthly.csv`, a current-vintage Stats SA index series, to
convert every nominal monthly market price to constant 2025 rand before forecasting,
ranking, and scoring:

```text
price_2025 = nominal_price * mean(CPI_2025_Jan_to_Dec) / CPI_observation_month
```

The twelve-month 2025 mean is computed from the committed monthly cells without
rounding the published annual value. Use decimal arithmetic and round only display
values. This retrospective conversion uses information unavailable at older
origins and is permitted only because this protocol makes no planting-time
publication claim.

### Frozen production assumptions

Version 1 freezes the staged calendar leads as scenario assumptions. Their source
cleanup remains future work; changing them requires a protocol amendment.

| Crop        | In-season planting months                   | Harvest offset months | Yield kg/ha |
| ----------- | ------------------------------------------- | --------------------: | ----------: |
| butternut   | Sep, Oct, Nov                               |                     5 |      22,500 |
| cabbage     | Jan, Feb, Mar, Apr, May, Nov, Dec           |                     3 |      75,000 |
| carrots     | Jan, Feb, Mar, Aug, Sep, Oct                |                     4 |      50,000 |
| green beans | Jan, Sep, Oct, Nov, Dec                     |                     3 |      10,000 |
| onions      | Feb, Mar                                    |                     7 |      42,500 |
| potatoes    | Jan, Feb, Jul, Aug, Sep, Oct                |                     5 |      45,000 |
| spinach     | Jan, Feb, Mar, Apr, Aug, Sep, Oct, Nov, Dec |                     3 |      20,000 |
| tomatoes    | Aug, Sep, Oct, Nov                          |                     3 |      62,500 |

Harvest offset is the ceiling of the staged midpoint plant-to-harvest duration
divided by 30 days. Yield is the arithmetic midpoint of the staged range; green
beans use its 10 t/ha point value. Nursery time is excluded from land occupancy.

Use the reviewed 2025 Elsenburg total allocatable variable costs and marketing
rates exactly as displayed:

| Crop        | Cost ZAR/ha | Marketing rate |
| ----------- | ----------: | -------------: |
| butternut   |   60,756.87 |          12.5% |
| cabbage     |  115,183.85 |          12.5% |
| carrots     |   68,312.94 |          12.5% |
| green beans |  136,357.03 |          12.5% |
| onions      |  108,783.41 |          12.5% |
| potatoes    |  181,097.86 |          12.5% |
| spinach     |  167,412.66 |          12.5% |
| tomatoes    |  168,968.20 |             0% |

Gross revenue is reduced by the marketing rate before subtracting cost. Working
capital interest and fixed costs are excluded. Source-displayed VAT treatment is
left unchanged: spinach and processing tomatoes state that prices include VAT;
the other six do not state an equivalent basis. Tomatoes use a processing budget
against fresh-market prices. Both limitations must appear in the report caveats.

## Forecasts

At each origin, construct training rows only from observation months before that
origin under the analytical next-month rule. Transform prices to constant 2025
rand before fitting.

- Historical range: linear empirical P10/P50/P90 for the target calendar month,
  requiring at least three eligible target-month observations.
- Diagnostic baseline: the same target month in the previous year when eligible.
- Challenger: separate deterministic LightGBM quantile models for P10/P50/P90;
  CPU, one thread, seed 20, deterministic column-wise training, 50 rounds, seven
  leaves, minimum leaf size 10, learning rate 0.05. Features are lags 2, 3, 4, 6
  and 12, target-month sine/cosine, and horizon. Require 36 complete training rows.
  Reconstruct each training row at its own origin, sort crossing quantiles, and
  reject nonfinite or nonpositive output.
- Method selection: per crop and harvest offset, mean of the three pinball losses
  over a trailing 36-month walk-forward window with at least 12 common scorable
  targets. A method missing a common target is disqualified. Historical range wins
  exact ties. Record fold counts, failures, scores, and the selected method.

Write the forecast ledger and `forecast_backtest.json`. Write the 96-row deployment
snapshot separately as `forecasts.parquet`; it is not the historical decision
ledger. All seeds and row ordering are fixed.

## Recommendations and scoring

For each audit-grid origin:

1. Determine in-season candidates from the frozen table.
2. Require one selected P50 forecast for every candidate; otherwise skip the row.
3. Calculate predicted monthly gross margin:

```text
((predicted_price_2025 * (1 - marketing_rate)) * yield_kg_per_ha
 - cost_2025_rand_per_ha) / harvest_offset_months
```

4. Recommend the greatest predicted margin, even if every margin is negative.
   Break exact ties by alphabetical crop identifier.
5. Freeze the recommendation before reading any realized target price.
6. Score the recommended and default crops using their realized harvest-month
   prices transformed to 2025 rand and the same frozen production assumptions.
   If either outcome is missing, record a skip.

A recommendation equal to the default is a no-switch decision. Otherwise the gain
is recommended actual margin minus default actual margin. Preserve zero gains,
losses, and negative margins.

## Metrics

Publish one alphabetical row per default plus `pooled`. Each contains decisions,
switch rate, switch win rate, median gain in rand, median percentage gain, P10 gain,
worst loss, and the 90% confidence interval for median gain.

- A win requires gain strictly greater than zero.
- Percentage gain is defined only when the actual default margin is positive;
  publish the excluded denominator.
- Worst loss is the lesser of zero and the minimum switch gain.
- Pooled values come from pooled decision rows, never averages of crop summaries.
- Bootstrap 10,000 planting-year cluster samples with seed 20, retaining every
  default comparison in a sampled year. Require at least two clusters and 90% valid
  nonempty-switch replicates. CI endpoints are the 5th and 95th percentiles of
  replicate medians. Otherwise publish null with a reason.

## Artifacts and reproducibility

The credential-free runner writes:

- `ml/forecast/results/<run_id>/forecasts.parquet`
- `ml/forecast/results/<run_id>/forecast_backtest.json`
- `ml/backtest/results/<run_id>/decision_backtest.json`
- `ml/backtest/results/<run_id>/decision_backtest.md`
- `ml/backtest/results/<run_id>/decision_ledger.parquet`
- `ml/backtest/results/<run_id>/slide_sentence.txt`
- a manifest containing code, protocol, configuration and input hashes, dependency
  versions, seed, scenario label, caveats, row counts and artifact hashes

The run ID is derived from those identities. Two clean runs must produce identical
artifact bytes. The runner must refuse real/current-vintage inputs until the
protocol history gate proves this file predates the first committed results.

The generated sentence template is:

> In a retrospective fixed-2025-input simulation of **N** scorable planting decisions (**START–END**), when Farmable recommended switching away from a farmer's usual crop, the switch earned more profit **X%** of the time, with a median increase of **R Y** per hectare per month (ranging from **A%** to **B%** across the 8 starting crops). Uses current-vintage Joburg Market history, fixed Western Cape production assumptions and retrospective inflation adjustment; it does not show what information was published at the historical planting date.

Every displayed number is generated from the JSON results. Synthetic runs retain
their warning and cannot use this sentence as real evidence.

## Required caveats

The report must disclose current-vintage/revision uncertainty, provisional calendar
assumptions, mixed or unknown VAT bases, the processing-tomato budget mismatch,
Western Cape costs applied to Johannesburg prices, missing post-2024 spinach data,
skipped late harvests, guideline rather than realized yields, and the limited number
of planting-year bootstrap clusters. It must not make claims about real farmer
income or historically available publications.
