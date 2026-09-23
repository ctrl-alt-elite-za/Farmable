# Issue #20 staged data inventory

**Checkpoint:** 23 September 2026. Original official workbooks for 2008–2024 have
now been inspected. All eight crops have twelve valid monthly Johannesburg prices
in each workbook. Matching official archive captures give conservative availability
bounds for 2008–2020; the 2021–2024 vintages remain unknown. An official quarterly
report partially covers late harvests through March 2025 but omits spinach.

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

1. Establish publication/revision evidence for the 2021–2024 Joburg workbooks.
   The 2008–2020 archive captures are conservative availability bounds rather than
   publication dates. Obtain spinach and any additional post-2024 harvest months;
   the audited quarterly report covers seven crops through March 2025.
2. Keep FAOSTAT producer prices separate from Joburg wholesale prices. The selected
   strict experiment does not authorize substitution.
3. Add source URLs, retrieval dates, vintages/availability dates, units, flags, and
   redistribution permissions to `SOURCES.md` before committing derived inputs.
   The 2025 Elsenburg PDFs now have hashes and extracted fields in
   `BUDGET_REVIEW.md`; the subtotal/marketing mapping is frozen, while historical
   vintages and VAT compatibility remain outstanding.
4. Reconcile the staged calendar with the chosen region and exact eight-crop
   contract. The current CSV includes pumpkin and beetroot and has no provenance
   metadata sufficient for a reproducible release. The official ARC booklets are
   now audited separately in `CALENDAR_REVIEW.md`; they leave material fields and
   protocol choices unresolved and do not validate the staged rows.
5. The committed Stats SA fallback supplies the complete 2025 reporting base;
   independently verify its transcription against the original PDF. It is not a
   historical-vintage feature input. See `SOURCES.md` and the information policy.

## Official workbook coverage audit

`market_workbook_audit.json` is the machine-readable evidence, including source
URLs/hashes and exact row locators. Every 2012–2024 year contributes twelve
positive, internally consistent monthly prices per crop. No missing or inconsistent
cells were found in these eight rows. The audit separately records conservative
official archive bounds for 2008–2020 and unknown availability for 2021–2024.

| Crop        | Exact workbook label | 2008–2011 training months | 2012–2024 months | Audited Oct 2024–Mar 2025 report months |
| ----------- | -------------------- | ------------------------: | ---------------: | --------------------------------------: |
| butternut   | BUTTERNUT SQUASHES   |                        48 |              156 |                                       6 |
| cabbage     | CABBAGE              |                        48 |              156 |                                       6 |
| carrots     | CARROTS              |                        48 |              156 |                                       6 |
| green_beans | GREEN BEANS          |                        48 |              156 |                                       6 |
| onions      | ONIONS               |                        48 |              156 |                                       6 |
| potatoes    | POTATOES             |                        48 |              156 |                                       6 |
| spinach     | SPINACH              |                        48 |              156 |                                       0 |
| tomatoes    | TOMATOES             |                        48 |              156 |                                       6 |

The quarterly report is a distinct PDF source; it is not silently spliced into the
annual workbooks. Its original bytes and visual page review are recorded in
`post_2024_market_source_audit.json`. Training-month counts do not establish that
every rolling validation fold has enough eligible, published observations.

**Decision: historical Joburg input remains blocked** by unknown 2021–2024
workbook vintages, missing post-2024 spinach coverage and unapproved source-splice
rules. Do not generate real decisions from this audit.
