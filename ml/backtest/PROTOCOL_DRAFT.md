# Issue #20 protocol proposal — not registered

**Evidence checkpoint:** 23 September 2026. The strict historical-information
requirement remains in force. The currently staged inputs do not support a real
backtest: the Joburg source contains only recent daily observations, FAOSTAT is a
distinct farm-gate series, and the official annual workbook links and 2025 budget
PDF links have not yet been verified at row/component level. Do not run or publish
decision outcomes until those checks and the cost-information policy are resolved.

This is a review draft, **not `PROTOCOL.md`**. It cannot pass the history gate and
must not authorize a real-data backtest. A finalized protocol must merge in its
own PR before any real decision evaluation. No results have been examined here.

## Fixed issue requirements

January 2012–December 2024 plantings. Eight default crops: butternut, cabbage,
carrots, green beans, onions, potatoes, spinach and tomatoes. Exclude beetroot
and pumpkins for missing costs. Disclose the processing-tomato budget and
Western Cape budget/guideline-yield assumptions. Use Joburg harvest-month
wholesale prices, with each crop's own occupied duration and guideline mid yield.

Gross margin is `(harvest price * yield - cost) / occupied months`, reported in
2025 ZAR per hectare per month. Predictions and recommendations must use only
information available strictly before the beginning of the planting month.

## Proposed executable settings (subject to source coverage and review)

- Historical range: linear empirical P10/P50/P90 for the target calendar month,
  at least three historical target-month observations.
- Baseline: same target month last year only if published before the origin.
  Treat it as a diagnostic comparator; production methods are historical range
  and LightGBM, consistent with the current #21 consumer's method enumeration.
- Challenger: separate LightGBM quantile fits; CPU, one thread, seeds 20,
  deterministic column-wise training, 50 rounds, 7 leaves, leaf minimum 10,
  learning rate 0.05. Lag months 2, 3, 4, 6, 12, target-month sine/cosine and
  horizon. At least 36 complete training records. Reconstruct each training
  record's features at its own planting origin. Sort predicted quantiles to
  correct crossings; reject nonpositive/nonfinite output.
- Selection: per crop and agreed pooled horizons, mean of three pinball losses,
  36-month trailing validation window with at least 12 published targets.
  Refit at each fold origin. All methods see the same targets; a method missing
  any required target is disqualified, with failure recorded. Prefer historical
  range on exact ties. The implemented selector currently handles one horizon
  per call; multi-horizon pooling still needs implementation.
- Require a forecast for every in-season candidate. Recommend the maximum P50
  predicted margin even when all margins are negative. Exact ties alphabetical.
  Missing realized outcome yields a skipped score, never a replacement crop.
- Compute switch statistics from scorable switches, preserving losses and ties.
  Count a win only for strictly positive gain. Percentage gain requires a positive
  actual default margin; publish the excluded percentage denominator.
- Quantiles use linear interpolation. Worst loss is `min(0, minimum gain)`.
  Pooled figures come from decision rows, not averages of crop summaries.
- Bootstrap: 10,000 seeded (20) planting-year cluster resamples retaining all
  default comparisons in each sampled year. At least two clusters and 90% valid
  nonempty-switch replicates; otherwise null with an explicit reason. CI endpoints
  are the 5th and 95th percentiles of replicate medians. Acknowledge limited
  year clusters and broken between-year dependence. This is a proposal, not
  evidence that these assumptions suit the final data.
- Produce eight alphabetical rows plus pooled, automatic exclusions/caveats,
  source hashes and a sentence generated from the same metrics. Display one
  decimal with half-even rounding. Undefined defaults produce insufficient
  evidence, not fabricated headline values. Synthetic artifacts carry a warning.

## Decisions required before registration

1. **Price source and coverage:** verify historical monthly Joburg prices, training
  history and post-2024 harvest coverage for all eight exact crops. The Department
  archive currently proves only that annual candidate workbooks are linked for
  2012–2024; inspect original workbook contents, aggregation, units and
  availability lags. Scrape dates and archive links alone are insufficient.
2. **Cost/CPI information policy:** fixed 2025 costs and future CPI can change
   historical recommendations. Choose historical cost vintages for a strict
   information claim, or obtain an explicit issue amendment for a fixed modern-cost
   scenario. The current issue's literal wording must not silently be weakened.
3. **Calendar and budgets:** source region, planting windows, harvest offsets,
   occupied duration, yield midpoint and cost subtotal/VAT/marketing treatment.
   The 2025 Elsenburg PDFs are dated leads, not verified historical cost inputs;
   inspect their components before deciding whether the experiment is a fixed
   modern-cost scenario or can make a strict information-availability claim.
4. **Selection:** settle baseline eligibility, horizon pooling, failure coverage,
   training minimums and availability rules from source inventory.
5. **Publication:** verify that the exact issue sentence's planting-time claim is
   supported by the selected scenario, not only by synthetic cutoff tests.

The snapshot export implements eight crops × twelve **planting-month numbers**,
with prices for subsequent harvests, 2025 ZAR/kg and explicit as-of/source metadata.
It also emits #21-compatible JSON. This is not a claim of a dated live forecast.

After these decisions: replace this proposal with the approved `PROTOCOL.md`,
merge it separately, then integrate the gated real runner, Colab workflow and
result manifests. The eventual run ID must include source/code/protocol/config
hashes; the current synthetic report hash is not that final experiment identity.
