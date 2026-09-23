# Issue #20 protocol proposal — not registered

**Evidence checkpoint:** 23 September 2026. The strict historical-information
requirement remains in force. The official workbooks now have verified monthly
Joburg coverage for 2008–2024. Official archive captures bound availability for
2008–2020, but 2021–2024 remain unresolved. An official quarterly report adds
October 2024–March 2025 outcomes for seven crops but omits spinach. Modern budget
fields have been extracted; historical costs, complete calendar values and VAT
compatibility remain missing; the cost-subtotal
mapping is frozen. FAOSTAT remains a distinct farm-gate series. Do not run or
publish decision outcomes until those source checks and protocol registration are
complete.

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
   workbooks now prove monthly content coverage for 2008–2024; see the committed
   source audit. Archived official payloads conservatively bound 2008–2020
   availability. Establish 2021–2024 release/revision evidence and obtain the
   missing post-2024 spinach observations. Scrape dates, server timestamps and
   workbook/PDF modification dates are insufficient.
2. **Cost/CPI information policy:** the user selected strict historical cost/input
   vintages. Fixed 2025 costs deflated by future CPI are prohibited for ranking.
   See `INFORMATION_POLICY.md` for the selected rule and executable counterexample.
   Historical source vintages and their release evidence still need verification.
3. **Calendar and budgets:** source region, planting windows, harvest offsets,
   occupied duration, yield midpoint and cost subtotal/VAT/marketing treatment.
   The Elsenburg subtotal/marketing mapping is frozen but the 2025 PDFs are not
   verified historical inputs. The ARC booklets have been reviewed page by page;
   `CALENDAR_REVIEW.md` records missing yield/duration fields, ambiguous units and
   unresolved region/cultivar/crop-identity choices. Obtain approved values and
   historical source versions published before each origin. A modern document's
   creation date cannot date its revised values.
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
