# Reference data for issue #20

**Goal:** stage the reference data issue #20's forecast model and decision backtest need
— historical crop prices, planting/harvest calendars, and weather — so that work isn't
blocked on re-scraping from scratch.

**Approach:** pulled the current (non-superseded) CSVs out of the
`sa-fresh-produce-market-analysis` scraper repo issue #20 names as a starting point, and
organized them by source under `ml/data/<source>/`:

- `joburg_market/` — daily Joburg Market wholesale prices (the scraper's own output)
- `faostat_producer_prices/` — FAOSTAT South Africa producer prices, 2010–2025, monthly
- `crop_calendar/` — GDARD planting/harvest/yield guidelines
- `rainfall/` — Open-Meteo daily rainfall for the growing regions

**Why FAOSTAT alongside Joburg data:** the Joburg scrape only covers 41 days so far — not
enough history for a monthly-range forecast. FAOSTAT gives 15 years of monthly data for
7 of the 8 crops, but it's farm-gate producer price, not Joburg wholesale; treat it as a
substitute with that difference documented, not a like-for-like source, until either the
scraper accumulates enough months or the two are reconciled.

**Not covered here, still needed:** Elsenburg cost-per-hectare budgets (all 8 crops) and
the CPI file (`ml/data/cpi_za_monthly.csv`) — neither exists in the scraped data.
