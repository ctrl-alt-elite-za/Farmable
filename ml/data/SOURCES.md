# Issue #20 public input provenance

## South African CPI: reporting snapshot

- Publisher: Statistics South Africa, P0141, **CPI History, Table B1**.
- Source URL: https://www.statssa.gov.za/publications/P0141/CPIHistory.pdf
- Retrieved through the web reader: **2026-09-23**. The visible source extended
  through July 2026; the checked-in subset covers January 2000–December 2025.
- Original PDF downloaded from the same URL on **2026-09-25**: 429,947 bytes,
  SHA-256 `45899dcddeaf30bd3317f813fa4300bfb99352681eb07179babe86f94f9430bfc`.
  It is a three-page file whose PDF metadata says it was created on
  8 September 2026; metadata is not a publication date. All 26 annual Table B1
  rows for 2000–2025 were compared with the committed transcription, including
  the displayed annual-average cells. They match exactly after converting
  decimal commas to points and normalizing whitespace.
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
- Limits: the original PDF is not redistributed. The numeric facts are attributed
  here; no claim of an identified redistribution licence is made. The verified
  current PDF does not establish what CPI vintage was public at any historical
  planting date.
- This is a **current-vintage snapshot**, not an archived release known to a
  farmer in 2012. Registered protocol version 1 explicitly uses it for retrospective
  constant-2025-rand transformation and disclaims historical publication-time
  availability. The deferred strict policy still prohibits that use; see
  `../backtest/INFORMATION_POLICY.md`. Source cleanup remains open.

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

These are current downloaded workbook versions. Archived HTTP-200 captures on
official DAFF/DALRRD URLs match the audited payloads for 2008 through 2020.
`market_workbook_audit.json` records the earliest matching capture timestamp as a
conservative availability bound for each of those files. It is not a publication
date, and a file is eligible only for planting origins strictly after its bound.
No matching historical official capture was found for 2021 through 2024, so those
records retain `available_on: null` and block historical use. Monthly observation
labels, current download times and file metadata are not release evidence. No
redistribution licence has been verified. Original workbooks remain in ignored
local scratch storage; the committed audit contains provenance/coverage metadata,
not prices. FAOSTAT stays a distinct farm-gate source and is not substituted.

The audited 17 workbooks were re-downloaded into ignored scratch storage on
23 September 2026 and every byte matched the committed SHA-256 audit. The archive
evidence improves the usable training history, but it does not clear the complete
2012–2024 experiment: the 2021–2024 workbook vintages remain unknown.

To reproduce, download each audit entry's URL under its original `filename` in a
local directory, copy the audit JSON there, and run:

```text
uv run --with xlrd==2.0.2 --with openpyxl==3.1.5 python scripts/audit_issue20_market_workbooks.py PATH/market_workbook_audit.json --output PATH/rechecked.json
```

The readers are temporary audit dependencies, not model/runtime dependencies.
Hashes must match before parsing. This command does not import data or run models.

### Follow-up: October 2024 through March 2025 market report

The official Department of Agriculture report [Crops and Markets First Quarter
2025](https://www.nda.gov.za/images/Branches/Economica%20Development%20Trade%20and%20Marketing/Statistc%20and%20%20Economic%20Analysis/statistical-information/crops-and-markets-1st-quarter-2025-.pdf)
was downloaded, hashed and visually reviewed page by page for the required crops.
It supplies monthly Johannesburg tonnes and R/ton from October 2024 through March
2025 for butternut, cabbage, carrots, green beans, onions, potatoes and tomatoes.
Spinach is absent. `post_2024_market_source_audit.json` records the file identity,
pages, fields and crop gap.

This report is useful candidate outcome coverage for late-2024 plantings, but it
does not complete the eight-crop contract. No matching archive capture or publisher
release record was found, so PDF metadata and the current server timestamp are not
treated as availability evidence. The official Statistics and Economic Analysis
contact route is recorded at <https://nda.gov.za/index.php/publication/322-sea-contacts>;
an official response is still needed for the missing spinach observations and
release/revision history. `PUBLISHER_DATA_REQUEST.md` contains a reviewable draft
request and response-acceptance rules; it has not been sent.

### Follow-up: original budget inspection

The eight 2025 Elsenburg PDFs and an older cabbage PDF were also downloaded and
their text inspected on 23 September 2026. `budget_source_audit.json` records
original-byte hashes and URLs. `BUDGET_REVIEW.md` records extracted dates,
regions, units, subtotals and explicit unresolved issues. This supersedes the
earlier download limitation; it does not approve modern costs for historical use.
The eight current budget files plus the older cabbage candidate were also
re-downloaded into ignored scratch storage and matched their committed hashes.
No download date, URL path, or PDF metadata was treated as a historical release
date.

### Follow-up: calendar source identified

The official [ARC production-guidelines page](https://www.arc.agric.za/arc-vopi/Pages/Production-Guidelines.aspx)
links the relevant source booklets:

- [Production Guideline for Summer Vegetables](https://www.arc.agric.za/arc-vopi/Leaflets%20Library/Production%20Guideline%20for%20Summer%20Vegetables.pdf)
  covers tomatoes, Swiss chard/spinach, cucurbits including butternut, and green
  beans.
- [Production Guideline for Winter Vegetables](https://www.arc.agric.za/arc-vopi/Leaflets%20Library/Production%20Guideline%20for%20Winter%20Vegetables.pdf)
  covers cabbage, carrots, onions and potatoes.

This identifies the primary calendar source family and supersedes the earlier
statement that the exact ARC documents had not been located. The booklets still
need file-level extraction and review before calendar verification is complete:
record the relevant crop/region planting windows, harvest offsets, occupied-month
mapping, guideline yield midpoint, document version/release evidence and
redistribution terms. Do not treat the staged calendar CSV or the Elsenburg budget
durations as verified replacements for those fields.

`calendar_source_audit.json` records the downloaded source hashes, sizes, page
counts, ARC copyright notices and crop topics. The originally recorded winter
response was a truncated 17,327,888-byte file that exposed zero pages. A fresh
response from the same official URL is a readable 38-page, 20,284,376-byte PDF;
the audit records both identities and treats the first only as superseded
provenance. `CALENDAR_REVIEW.md` records the complete page-level field review.

The summer booklet exposes an RSA sowing/planting chart and guidance for green
beans, Swiss chard/spinach, tomatoes and cucurbits; the winter booklet covers
cabbage, carrots, onions and potatoes. Material fields remain absent or ambiguous:
several crops lack yield ranges or explicit durations, onions lack a planting
window, butternut's class-level yield unit is unsafe, and regional/cultivar choices
remain. Historical release dates and redistribution permission are also unknown.
No calendar row is imported from the PDFs.

### Land Bank market-tomato budget candidate

The Land Bank [2025/26 vegetable enterprise budget](https://landbank.co.za/Media-Centre/Publications/2026/Vegetable%20Enterprise%20Budget%202025%20print.pdf)
was downloaded on 25 September 2026 and inspected at the original-file level.
Its 4,637,725 bytes have SHA-256
`50a329bd452770b8dc02d0f8e1b69ab7ab95d921c7982cf47e3b93b13a5820c7`.
See `LANDBANK_TOMATO_REVIEW.md` for the tomato fields, arithmetic and blockers.
The PDF is not redistributed, and its copyright notice requires permission for
copying or reprinting. It is a candidate for a future registered evaluation, not
an input to the completed version 1 result.
