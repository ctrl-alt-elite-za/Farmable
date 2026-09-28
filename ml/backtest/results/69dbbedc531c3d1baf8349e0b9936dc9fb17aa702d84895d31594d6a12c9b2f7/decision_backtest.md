# Decision backtest

Data kind: **historical**.
Scenario: retrospective fixed-2025-input simulation (not historical publication evidence).
Ledger coverage: 2012-01–2024-12 (bounds; synthetic months may be sparse).

Amounts: 2025 ZAR per hectare per occupied month. Rates are percentages.

| Default | Decisions | Switch rate | Switch wins | Median gain R | Median gain % | P10 R | Worst loss R | Median CI90 R |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |
| butternut | 30 | 100.0 | 100.0 | 35048.7 | 853.0 | 14784.0 | 0.0 | [27898.5, 39303.2] |
| cabbage | 75 | 0.0 | n/a | n/a | n/a | n/a | n/a | n/a |
| carrots | 64 | 51.6 | 75.8 | 13117.8 | 40.0 | -10506.9 | -33021.5 | [8039.3, 15146.0] |
| green_beans | 51 | 100.0 | 100.0 | 45309.8 | 365.6 | 18434.5 | 0.0 | [38152.2, 58521.7] |
| onions | 22 | 100.0 | 90.9 | 30133.5 | 354.0 | 6059.3 | -16209.2 | [24743.2, 36459.2] |
| potatoes | 63 | 82.5 | 100.0 | 32097.7 | 357.9 | 17533.7 | 0.0 | [27576.0, 37705.1] |
| spinach | 95 | 100.0 | 100.0 | 66966.5 | 1095.8 | 45619.1 | 0.0 | [61036.4, 75820.7] |
| pooled | 400 | 70.8 | 96.5 | 44295.8 | 266.4 | 14131.6 | -33021.5 | [39204.6, 47638.5] |

Undefined values and their reasons are recorded in decision_backtest.json.

Tomatoes excluded: No compatible reviewed fresh-market tomato production budget; the published version 1 result paired a processing budget with fresh-market prices.

Amendment 2 was registered after the version 1 result was observed.

- Simulated decisions are not observed farmer incomes.
- Guideline yields and Western Cape budgets are assumptions.
- Year-cluster resampling retains dependence within years, but not between years.
- At most 13 planting-year clusters limit confidence-interval interpretation.
- Current-vintage Johannesburg history has unresolved publication/revision uncertainty.
- The next-month observation cutoff is analytical, not a publisher release-date claim.
- Current-vintage CPI and the full 2025 mean enter retrospective prediction and scoring.
- Planting calendars, harvest offsets and guideline yields are provisional frozen assumptions.
- VAT bases are mixed or unknown; source-displayed treatment has not been harmonized.
- Western Cape production costs are applied to Johannesburg market prices.
- Post-2024 spinach prices are missing; the Q1 2025 candidate source is not spliced in.
- Missing realized prices for late harvests remain explicit skips, not zero gains.
- Working-capital interest and fixed costs are excluded from the listed gross margins.
- Tomatoes are excluded from production and switching calculations; a separate price-only forecast is available.
- Amendment 2 was registered after the version 1 result was observed.
