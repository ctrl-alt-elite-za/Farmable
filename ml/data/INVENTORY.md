# Issue #20 staged data inventory

**Checkpoint:** 23 September 2026. The official Department of Agriculture archive
was inspected as a source lead. It publishes annual fresh-produce workbook links
for 2012 through 2024, but the archive page does not establish that each workbook
contains monthly Johannesburg rows for the eight required crops. Workbook-level
inspection remains required; the links alone do not clear the historical-price
blocker.

This document is generated from the existing Git ref `origin/issue-20-reference-data`.
It records what is actually staged and the limits that must be resolved before a
real forecast or decision backtest. It does not copy source data or claim that a
source is available outside this ref.

Run the deterministic inventory from the repository root:

```text
python scripts/inventory_issue20_data.py --ref origin/issue-20-reference-data
```

The command reads each CSV as an exact Git blob, reports its SHA-256, columns, rows,
crop values, date/year coverage, and provenance limitations as JSON. `--repo` accepts
another local checkout. It does not fetch, switch branches, download inputs, connect
to a database, or run a model/backtest.

## Verified staged snapshot

The staged ref is commit `69ff3904dd308f385b9d0b4115fac2cac92429c15`.

| Dataset                                                    | Staged evidence                                                                                                        | Coverage and unit                                                                                                               | Provenance and blocker                                                                                                                                                                                                                                   |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `faostat_producer_prices/faostat_sa_veg_monthly.csv`       | Normalized rows with `crop`, `item_faostat`, `year`, `month_num`, `month_name`, `price_lcu_per_tonne`, and `flag`.     | The staged rows run from 2010 through 2024 and are in LCU per tonne. This is producer/farm-gate price, not Joburg wholesale.    | README attributes this to FAOSTAT, but the staged file has no download date, vintage, or release availability metadata. It cannot establish planting-time information availability.                                                                      |
| `faostat_producer_prices/faostat_sa_veg_annual.csv`        | Normalized annual rows with `price_lcu_per_tonne` and `flag`.                                                          | Annual producer prices; the staged normalized file ends in 2024.                                                                | Useful for coverage checks, but annual and monthly rows must not be mixed as observations. Preserve FAOSTAT flags.                                                                                                                                       |
| `faostat_producer_prices/faostat_prices_ZA_raw_subset.csv` | Wide FAOSTAT export with annual and monthly elements, LCU and SLC/US dollar/index rows, and year columns through 2025. | Header years are not proof of populated monthly values; the file mixes elements and flags.                                      | Filter one element/unit and verify non-empty rows by month before use. The staged file has no vintage/release dates.                                                                                                                                     |
| `joburg_market/produce_prices_master.csv`                  | Daily scraper output with total value sold, total quantity, total kg, market, and `date_scraped`.                      | The staged README says 41 days at this source revision; dates are 2026 daily observations. It is not 2012–2024 monthly history. | Source page is [Joburg Market daily prices](https://joburgmarket.co.za/jhb-market/dailyprices.php). No redistribution licence, grade/package normalization, or historical archive is recorded. A R/kg figure would be derived as total value / total kg. |
| `crop_calendar/crop_calendar.csv`                          | Ten crop rows with planting months, sow-to-transplant days, plant-to-harvest days, and yield ranges in t/ha.           | Includes the eight issue crops plus beetroot and pumpkin. Planting months are scenario windows, not historical observations.    | README names GDARD Vegetable Production Guidelines and ARC Growing Green Beans, but the CSV has no URL, retrieval date, version, region, or licence.                                                                                                     |
| `rainfall/rainfall_master.csv`                             | Daily `date`, `region`, and `rainfall_mm`.                                                                             | Staged dates are 2026-07-08 through 2026-09-12 across named regions.                                                            | README attributes this to Open-Meteo, but query coordinates and retrieval metadata are absent. It is regional context, not a crop-specific historical price input.                                                                                       |

## Required blockers before real results

1. Download and inspect the official Department of Agriculture annual fresh-produce
   workbooks for 2012–2024 and prove that Joburg/product/month rows exist, with
   units, aggregation definitions and publication/availability metadata. The archive
   links are evidence that candidate files exist, not evidence that they satisfy the
   required backtest period. The staged scraper cannot satisfy that period.
2. Decide whether FAOSTAT producer prices are an explicitly labelled substitute for
   Joburg wholesale prices. Do not silently merge the two series or call producer prices
   Joburg prices.
3. Add source URLs, retrieval dates, vintages/availability dates, units, flags, and
   redistribution permissions to `SOURCES.md` before committing derived inputs.
   The 2025 Elsenburg budget links are likewise only dated source leads until each
   budget's region, production period, yield, cost subtotal, VAT and marketing
   treatment have been transcribed and checked.
4. Reconcile the staged calendar with the chosen region and exact eight-crop contract.
   The current CSV includes pumpkin and beetroot and has no provenance metadata sufficient
   for a reproducible release.
5. The FRED `ZAFCPIALLMINMEI` series currently ends at January 2025, so it cannot by
   itself provide the PRD's complete twelve-month 2025 reporting base. Choose an official
   Stats SA fallback or amend the CPI-base rule before freezing the protocol.
