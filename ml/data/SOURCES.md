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
  recommendation ranking. The strict historical cost/CPI policy remains open.

## Prices, costs and calendars

See `INVENTORY.md` for the cached data branch. No historical Joburg wholesale
dataset, verified cost CSV or verified regional calendar is supplied by this
change. FAOSTAT producer prices and combined commodities must not silently
substitute for the issue's required market/crop series.

No real crop-switching profit outcome has been computed.
