# Issue #20 public input provenance

## South African CPI: reporting snapshot

- Publisher: Statistics South Africa, P0141, **CPI History, Table B1**.
- Source URL: https://www.statssa.gov.za/publications/P0141/CPIHistory.pdf
- Retrieved through the web reader: **2026-09-23**. The visible source extended
  through July 2026; the checked-in subset covers January 2000–December 2025.
- Series: headline **index levels**, December 2024 = 100. These are not inflation
  percentages. Primary urban areas through 2008, all urban areas from 2009;
  the publisher describes its linked series as a continuous index.
- Fallback rationale: the specified FRED series does not contain twelve 2025
  months. This entire subset uses the Stats SA series; no FRED/Stats SA splice
  or application-side rebasing is performed.
- Extraction: `statssa_cpi_table_b1.txt` is an attributed transcription of the
  web reader's extracted table. Decimal commas become decimal points. Run
  `uv run python scripts/build_issue20_cpi.py` to regenerate the monthly CSV.
  The parser checks 26 years and 12 months per year; published annual averages
  are retained in the transcription but excluded from monthly observations.
- File SHA-256:
  - `statssa_cpi_table_b1.txt`:
    `c1efd7bb9d0e3f88c8e390766e04910c32727750f3306cb3de174335b3b1be28`
  - `cpi_za_monthly.csv`:
    `7a02be81e4e719bf86da93a95e6ddea4d93e607fa2fc306d95e234c4b384bbce`
- The reporting base is the arithmetic mean of the twelve displayed monthly
  2025 levels: `1229.9 / 12`, rather than the source's rounded `102.5` annual cell.
  January 2012 is `53.0`; R100 then converts to R193.38 at two decimal places.
- Limits: direct HTTP download returned an HTML protection page, not the PDF.
  The hashes above identify the transcription and generated CSV, **not original
  PDF bytes**. Independent comparison to a locally downloaded original remains
  outstanding. The original PDF is not redistributed. The numeric facts are
  attributed here; no claim of an identified redistribution licence is made.
- This is a **current-vintage reporting snapshot**, not archived releases known
  to a farmer in 2012. Do not feed its 2025 base or later revisions into historical
  recommendation ranking. The user selected strict historical vintages; see
  `../backtest/INFORMATION_POLICY.md`. Source release evidence remains open.

## Prices, costs and calendars

See `INVENTORY.md` for the cached data branch. No historical Joburg wholesale
dataset, verified cost CSV or verified regional calendar is supplied by this
change. FAOSTAT producer prices and combined commodities must not silently
substitute for the issue's required market/crop series.

### 23 September 2026 initial source check

The official Department of Agriculture [fresh-produce archive](https://www.nda.gov.za/index.php/publication/336-fresh-produce)
exposes annual workbook links for 2012 through 2024. This confirms a plausible
source family, but not the required contents: no workbook was accepted as a
canonical input until its sheets prove monthly Johannesburg/product rows, units,
aggregation rules and publication availability. The archive therefore does not
yet support a strict 2012–2024 information-available backtest.

That initial check was superseded by the original-file inspections below.

No real crop-switching profit outcome has been computed.

### Follow-up: original workbook inspection

Original files for every year 2008–2024 were downloaded on 23 September 2026
from the archive above. `market_workbook_audit.json` records their direct URLs,
original filenames, byte lengths, SHA-256 hashes, sheet and price-row locators,
and per-crop valid/missing/inconsistent month lists. It supersedes the earlier
statement that workbook contents had not been inspected.

All seventeen `T6 JHB` sheets have monthly Johannesburg mass (T), sales value (R)
and average price (R/T). The audit verifies the January–December header, exact
product aliases and positive numeric mass/value/price cells. For each accepted
month, reported R/T agrees with sales value divided by tonnes to tolerance
`max(0.01 R/T, 1e-6 relative)`. Convert R/T to R/kg by dividing by 1,000; do not
average annual prices into months. Current and prior-year totals are excluded.
The 2020/2021 product labels are on mass rows; other inspected years use value rows.
Blank, nonpositive, nonnumeric or inconsistent cells would be flagged, not imputed.

These are current downloaded workbook versions. A search of the official archive
on 23 September 2026 found annual links but no historical publication or revision
dates. Each audit record therefore carries `available_on: null`,
`availability_status: unknown_blocks_historical_use`, and the reason. Monthly
observation labels cannot establish when those values became public. No redistribution
licence has been verified. Original workbooks remain in ignored local scratch
storage; the committed audit contains provenance/coverage metadata, not prices.
FAOSTAT stays a distinct farm-gate source and is not substituted.

To reproduce, download each audit entry's URL under its original `filename` in a
local directory, copy the audit JSON there, and run:

```text
uv run --with xlrd==2.0.2 --with openpyxl==3.1.5 python scripts/audit_issue20_market_workbooks.py PATH/market_workbook_audit.json --output PATH/rechecked.json
```

The readers are temporary audit dependencies, not model/runtime dependencies.
Hashes must match before parsing. This command does not import data or run models.

### Follow-up: original budget inspection

The eight 2025 Elsenburg PDFs and an older cabbage PDF were also downloaded and
their text inspected on 23 September 2026. `budget_source_audit.json` records
original-byte hashes and URLs. `BUDGET_REVIEW.md` records extracted dates,
regions, units, subtotals and explicit unresolved issues. This supersedes the
earlier download limitation; it does not approve modern costs for historical use.
