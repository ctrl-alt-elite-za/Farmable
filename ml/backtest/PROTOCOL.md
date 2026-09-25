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

### Amendment 2 — 25 September 2026: seven-default decision evaluation

The completed version 1 result, merged in PR #85, exposed an incompatible input
pairing: it valued fresh-market Johannesburg tomato prices using a processing-
tomato production budget with a 0% marketing rate. Tomatoes were also the only
default with no scorable switches. The project owner directed us to discard the
tomato **production assumptions** rather than infer a replacement cost, yield or
marketing rate from another source. This amendment is motivated by source
compatibility; it does not recast the observed version 1 result as successful.

This is a **new seven-default decision evaluation**, not a correction of version 1.
The original 1,248-key decision ledger, reports, manifests and 96-row snapshot
remain immutable and labelled as version 1. The amended result must be committed
in a separate result folder and displayed alongside version 1, including version
1's `INSUFFICIENT EVIDENCE` sentence and tomato caveat. No amended real decision
evaluation may run until this amendment is independently merged on `main`.

- Decision defaults and recommendation candidates are exactly butternut, cabbage,
  carrots, green beans, onions, potatoes and spinach. Tomatoes are excluded from
  both roles because no reviewed tomato production budget matches the fresh-
  market price series. The exclusion and reason must appear in the result JSON,
  table and sentence. Beetroot and pumpkins retain their version 1 exclusions.
- The audit grid is January 2012–December 2024 for each of these seven defaults:
  1,092 unique default/month keys. Preserve explicit out-of-season, missing-
  forecast and missing-realized-price skips. Do not retroactively select a
  different candidate when any required forecast or realized price is missing.
- Use the same 17 audited market workbooks, current-vintage CPI file, analytical
  next-month cutoff, forecast methods, per-origin walk-forward selection,
  non-tomato calendar/yield/cost/marketing assumptions, margin formula, ties,
  scoring rules, bootstrap and display rounding as version 1. No value is tuned
  from the observed version 1 gains. The remaining seven crops use their exact
  version 1 source values and 2025-rand basis.
- Tomato **price** forecasts remain available in a separate price-only artifact.
  At a fixed 1 January 2025 cutoff, use version 1's pre-2025 seasonal historical
  range method to forecast each January–December 2025 target calendar month.
  Record crop, market, target month, P10/P50/P90 in 2025 ZAR/kg, method, cutoff
  and source hashes. The artifact has no planting month, harvest offset, yield,
  cost, marketing rate or profit field. These forecasts do not enter the
  seven-default candidate set, profit calculation or pooled statistic. The
  version 1 deployment snapshot is not regenerated or relabelled by this
  amendment; its tomato economics remain an archived version 1 limitation and
  must not be activated as corrected advice.
- Calculate the same metric fields for all seven defaults and pooled from the new
  decision ledger. The table lists the seven defaults alphabetically plus pooled.
  If any default has zero scorable switches or another undefined required
  statistic, write `INSUFFICIENT EVIDENCE` and its reason instead of a headline.
  Otherwise generate the version 1 retrospective sentence with “7 starting
  crops” and the explicit clause “Tomatoes excluded: no compatible reviewed
  fresh-market production budget.” All numbers come from the amended JSON.
- Give the amended run a distinct scenario ID and content-derived run ID. Record
  this amendment's merged mainline commit, all input/code hashes and the version
  1 run ID in its manifest. Write new decision ledger, JSON report, Markdown table
  and generated sentence, plus the 12-row tomato price-only artifact. Include a
  version comparison that shows both complete
  result sets and explains the different crop universe; never describe a change
  in pooled gains as an improvement caused by model skill.

The sections below remain the **version 1** protocol. Amendment 2 overrides only
the decision universe, result-grid size, tomato exclusion, output packaging and
seven-default sentence wording listed above. It does not change the archived
version 1 forecast/deployment artifacts or their consumer contract.

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
