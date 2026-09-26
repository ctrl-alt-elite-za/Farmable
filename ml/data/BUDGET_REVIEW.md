# Elsenburg budget source review

Downloaded original PDFs, rendered both pages of every budget, and visually
inspected all 16 pages on 23 September 2026. `budget_source_audit.json` identifies
each original file by URL and SHA-256. The numbers below are source-budget inputs,
not Farmable backtest outcomes. All are Western Cape, one-hectare budgets. These
modern revisions are **not approved historical inputs**. Document update dates do
not prove publication dates.

| Crop        | Budget locality                         | Developed  | Updated    | Soil       | Yield                | Months | VAT statement |
| ----------- | --------------------------------------- | ---------- | ---------- | ---------- | -------------------- | -----: | ------------- |
| butternut   | Witzenberg, Cape Winelands              | 2013-09-01 | 2025-09-16 | sandy-loam | 23.25 t/ha           |      6 | not stated    |
| cabbage     | Phillipi, Cape Metropole                | 2015-03-30 | 2025-03-19 | sandy      | 51.15 t/ha           |      3 | not stated    |
| carrots     | Phillipi, Cape Metropole                | 2016-06-30 | 2025-03-12 | sandy      | 55,800 kg/ha         |      3 | not stated    |
| green_beans | Stellenbosch, Cape Winelands            | 2018-07-09 | 2025-03-17 | sandy-loam | 14,400 kg/ha         |    2.5 | not stated    |
| onions      | Witzenberg, Cape Winelands              | 2014-03-31 | 2025-09-04 | sandy-loam | 60.45 t/ha           |      6 | not stated    |
| potatoes    | Witzenberg, Cape Winelands              | 2014-03-31 | 2025-09-04 | sandy-loam | 51.15 t/ha           |      6 | not stated    |
| spinach     | Kuilsriver/Kraaifontein, Cape Metropole | 2015-05-31 | 2025-08-26 | sandy      | 35 t/ha              |      3 | included      |
| tomatoes    | Lutzville, North West Coast             | 2018-07-24 | 2025-08-23 | sandy-clay | 100 t/ha, processing |      3 | included      |

All financial fields below are displayed rand per hectare. “Marketing” is 12.5%
for every crop except processing tomatoes, where it is 0%.

| Crop        | Gross income | Marketing | After marketing | Direct variable | Indirect variable | Total variable | GM above direct | GM above total | Interest | Margin above specified |
| ----------- | -----------: | --------: | --------------: | --------------: | ----------------: | -------------: | --------------: | -------------: | -------: | ---------------------: |
| butternut   |   189,297.08 | 23,662.14 |      165,634.95 |       49,234.09 |         11,522.78 |      60,756.87 |      116,400.85 |     104,878.08 | 3,189.74 |             101,688.34 |
| cabbage     |   273,141.00 | 34,142.63 |      238,998.38 |      111,602.23 |          3,581.62 |     115,183.85 |      127,396.14 |     123,814.53 | 3,167.56 |             120,646.97 |
| carrots     |   407,898.00 | 50,987.25 |      356,910.75 |       65,751.61 |          2,561.33 |      68,312.94 |      291,159.14 |     288,597.81 | 1,878.61 |             286,719.21 |
| green_beans |   332,928.00 | 41,616.00 |      291,312.00 |      134,857.36 |          1,499.68 |     136,357.03 |      156,454.64 |     154,954.97 | 3,124.85 |             151,830.12 |
| onions      |   407,078.76 | 50,884.85 |      356,193.92 |      100,925.07 |          7,858.34 |     108,783.41 |      255,268.85 |     247,410.51 | 5,711.13 |             241,699.38 |
| potatoes    |   245,176.78 | 30,647.10 |      214,529.69 |      173,140.11 |          7,957.75 |     181,097.86 |       41,389.58 |      33,431.82 | 9,507.64 |              23,924.19 |
| spinach     |   577,447.40 | 72,430.93 |      505,016.48 |      164,352.08 |          3,060.58 |     167,412.66 |      342,664.39 |     339,603.81 | 4,394.58 |             335,209.23 |
| tomatoes    |   270,000.00 |      0.00 |      270,000.00 |      156,812.16 |         12,156.03 |     168,968.20 |      113,187.84 |     101,031.80 | 4,435.42 |              96,596.39 |

These are transcribed displayed subtotals; some rounded components differ from the
displayed total by one cent. Do not silently change source amounts to reconcile
display rounding. Spinach and processing-tomato PDFs explicitly state that prices
include VAT. Equivalent VAT treatment is not stated in the other six budgets, so
it cannot be inferred.

For the experiment formula, `cost_rand_per_ha` is the **total allocatable variable
cost** (direct plus indirect). Gross Joburg revenue must first be reduced by the
source-vintage marketing percentage, so the existing arithmetic receives a net
price. Working-capital interest is excluded because it is below the source's
“gross margin above total allocatable variable costs” line; fixed costs and the
source sensitivity analysis are also excluded. Direct-only costs would omit fuel
and repairs. The source's fixed marketing rand amount is not imported because it
embeds that budget's yield and price. This field mapping is frozen, but no row is
importable until its historical vintage and compatible VAT basis are verified.

The older cabbage file at the 2022/04 URL states a latest update of 10 March 2021
and a creation date of 30 March 2015. It reports yield in heads, unlike the 2025
tonne-based budget. Neither date supports using its values in 2012, and an
undocumented head-to-kg conversion is prohibited.

## Calendar and historical-input blockers

For **each of the eight crops**, historical cost releases available before the
required origins remain missing. Original publication dates and redistribution
permissions remain unverified for these downloads. No normalized import-ready
cost record is supplied.

The official ARC summer and winter vegetable booklets are now downloaded, hashed
and reviewed in `CALENDAR_REVIEW.md`. They provide useful planting and harvest
evidence but do not provide a complete canonical record for any automatic import:
material yield/duration fields are absent for several crops, some statements are
ambiguous, and region, cultivar/type and spinach/Swiss-chard identity choices
remain. The staged CSV still has no URL, hash, version or release date and does not
match the traceable source contract. Its values remain leads, not verified inputs.
The growing periods and yields above belong to the budgets and cannot substitute
for missing calendar fields. Processing tomatoes remain incompatible with
fresh-market prices without an explicit, reviewed assumption.

Consequently calendar verification, historical cost vintages, VAT reconciliation
and protocol registration remain open.

## Market-tomato candidate for a future evaluation

Land Bank publishes a 2025/26 market-tomato budget with a different yield,
marketing rate and variable-cost basis. Its original-byte hash, source arithmetic,
rights notice and unresolved comparability questions are recorded in
`LANDBANK_TOMATO_REVIEW.md`. It does not alter the registered version 1 inputs or
clear the historical-vintage, calendar, VAT and redistribution gaps above.
