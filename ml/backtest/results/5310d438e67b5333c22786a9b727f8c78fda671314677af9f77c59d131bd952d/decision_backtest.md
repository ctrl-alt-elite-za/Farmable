# Decision backtest

Data kind: **historical**.
Scenario: retrospective fixed-2025-input simulation (not historical publication evidence).
Ledger coverage: 2012-01–2024-12 (bounds; synthetic months may be sparse).

Amounts: 2025 ZAR per hectare per occupied month. Rates are percentages.

| Default     | Decisions | Switch rate | Switch wins | Median gain R | Median gain % |   P10 R | Worst loss R | Median CI90 R        |
| ----------- | --------: | ----------: | ----------: | ------------: | ------------: | ------: | -----------: | -------------------- |
| butternut   |        30 |       100.0 |       100.0 |      146676.7 |        3063.4 | 97983.5 |          0.0 | [136626.8, 173831.5] |
| cabbage     |        75 |        13.3 |       100.0 |      122745.8 |         330.8 | 71980.8 |          0.0 | [78304.7, 169414.6]  |
| carrots     |        64 |       100.0 |        87.5 |       35595.3 |          83.6 | -4493.8 |     -33021.5 | [22177.1, 45811.4]   |
| green_beans |        52 |       100.0 |       100.0 |      125363.5 |        1021.1 | 32053.2 |          0.0 | [108517.4, 135486.5] |
| onions      |        22 |       100.0 |        90.9 |       30133.5 |         354.0 |  6059.3 |     -16209.2 | [24743.2, 36459.2]   |
| potatoes    |        63 |        82.5 |       100.0 |       96609.3 |         747.1 | 27164.6 |          0.0 | [88624.7, 112698.0]  |
| spinach     |        96 |       100.0 |       100.0 |       90357.9 |        1928.2 | 48130.3 |          0.0 | [83555.2, 93957.7]   |
| tomatoes    |        42 |         0.0 |         n/a |           n/a |           n/a |     n/a |          n/a | n/a                  |
| pooled      |       444 |        73.4 |        96.9 |       91473.2 |         404.0 | 18559.4 |     -33021.5 | [82403.3, 95553.1]   |

Undefined values and their reasons are recorded in decision_backtest.json.

- Simulated decisions are not observed farmer incomes.
- Guideline yields and Western Cape budgets are assumptions.
- Tomatoes use a processing-tomato budget, not a fresh-market budget.
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
