# Elsenburg budget source review

Downloaded original PDFs and inspected extracted text on 23 September 2026.
`budget_source_audit.json` identifies each original file by URL and SHA-256.
The numbers below are source-budget inputs, not Farmable backtest outcomes.
All are Western Cape, one-hectare budgets. These modern revisions are **not
approved historical inputs**. Document update dates do not prove publication dates.

| Crop        | Budget locality                         | Latest update in PDF | Budget yield         | Growing months | Direct variable R/ha | Indirect variable R/ha | Total variable R/ha | Marketing |
| ----------- | --------------------------------------- | -------------------- | -------------------- | -------------: | -------------------: | ---------------------: | ------------------: | --------- |
| butternut   | Witzenberg, Cape Winelands              | 2025-09-16           | 23.25 t/ha           |              6 |            49,234.09 |              11,522.78 |           60,756.87 | 12.5%     |
| cabbage     | Phillipi, Cape Metropole                | 2025-03-19           | 51.15 t/ha           |              3 |           111,602.23 |               3,581.62 |          115,183.85 | 12.5%     |
| carrots     | Phillipi, Cape Metropole                | 2025-03-12           | 55,800 kg/ha         |              3 |            65,751.61 |               2,561.33 |           68,312.94 | 12.5%     |
| green_beans | Stellenbosch, Cape Winelands            | 2025-03-17           | 14,400 kg/ha         |            2.5 |           134,857.36 |               1,499.68 |          136,357.03 | 12.5%     |
| onions      | Witzenberg, Cape Winelands              | 2025-09-04           | 60.45 t/ha           |              6 |           100,925.07 |               7,858.34 |          108,783.41 | 12.5%     |
| potatoes    | Witzenberg, Cape Winelands              | 2025-09-04           | 51.15 t/ha           |              6 |           173,140.11 |               7,957.75 |          181,097.86 | 12.5%     |
| spinach     | Kuilsriver/Kraaifontein, Cape Metropole | 2025-08-26           | 35 t/ha              |              3 |           164,352.08 |               3,060.58 |          167,412.66 | 12.5%     |
| tomatoes    | Lutzville, North West Coast             | 2025-08-23           | 100 t/ha, processing |              3 |           156,812.16 |              12,156.03 |          168,968.20 | 0%        |

These are transcribed displayed subtotals; some rounded components differ from the
displayed total by one cent. Do not silently change source amounts to reconcile
display rounding. Independent visual/component reconciliation remains required.

Spinach and processing-tomato PDFs explicitly state that prices include VAT.
Equivalent VAT treatment was not established from the other six extracted texts;
do not infer exclusion or inclusion from silence. Marketing costs are shown
separately from total allocatable variable costs. Budgets also show working-capital
interest separately in their analysis; its relation to the selected cost subtotal
needs explicit review. With gross Joburg sales prices, simply subtracting the
variable subtotal omits the separately displayed marketing deduction. Using the
budget's fixed marketing rand amount would embed its own price/yield assumptions.
No cost subtotal is approved until that treatment and VAT basis are reconciled
with the registered formula and historical vintages.

The older cabbage file at the 2022/04 URL states a latest update of 10 March 2021
and a creation date of 30 March 2015. It reports yield in heads, unlike the 2025
tonne-based budget. Neither date supports using its values in 2012, and an
undocumented head-to-kg conversion is prohibited.

## Calendar and historical-input blockers

For **each of the eight crops**, historical cost releases available before the
required origins remain missing. Original publication dates and redistribution
permissions remain unverified for these downloads. No normalized import-ready
cost record is supplied.

For **each of the eight crops**, independently sourced regional planting windows,
harvest offsets, occupied months and guideline yield midpoints remain unverified.
The growing periods and yields above belong to the budgets and cannot substitute
for the requested calendar. Green beans' 2.5-month budget duration also needs a
registered harvest-month mapping. Processing tomatoes remain incompatible with
fresh-market prices without an explicit, reviewed assumption; do not hide this
behind the canonical `tomatoes` name.

Consequently R03's cost-subtotal and calendar tasks, the source-specific portion
of R04, and protocol registration remain open.
