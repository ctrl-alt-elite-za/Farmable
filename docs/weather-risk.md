# Location-specific historical weather exposure (#21)

This implementation is independent of #20, PR #61 and the local forecast
contingency. It does not train a model, change prices, derive soil properties or
change the frontend. `weather_risk` is a discriminated union; the existing
`unavailable` response is unchanged. Available results are historical **weather
exposure frequencies**, not probabilities of crop failure or a live forecast.

## Location, privacy and execution

Saving a section through the authenticated REST/sync path inserts a weather job
in the **same database transaction**. No HTTP call occurs in the save request.
WGS84 GeoJSON `Point` and `Polygon` exterior rings are supported. A polygon uses
its bounding-box centre, not a claimed surveyed centroid. Coordinates round to
the nearest 0.1 degree (decimal half-away-from-zero). Malformed, unsupported or
dateline-spanning boundaries produce unavailable weather, not a guessed location;
legacy section validation and saved boundaries are unchanged.

Only integer-tenth rounded coordinates reach the Open-Meteo adapter. No section,
farm or user ID, exact boundary, authentication token or name is transmitted.
Shared jobs contain only the grid cell, policy hash, historical period and queue
state. The key changes when any of these inputs changes. Two farms in one cell
reuse one result; reads remain owner-authorized before consulting that cache.
Removing/moving a boundary cannot expose the old cell's result.

The existing worker process runs one weather slot, independent of photo storage
configuration. `INTEGRATIONS_MODE=disabled` does not start it. Fake mode is still
restricted to CI/staging and produces explicitly labelled synthetic results.
Live reads refuse synthetic cache entries and vice versa. On mode change the
worker recomputes a ready job of the other kind; production cannot silently use
test weather.

Jobs are durable ORM rows, not in-process background callbacks. Workers claim
with PostgreSQL `FOR UPDATE SKIP LOCKED`; a two-minute lease and fencing token
prevent an expired worker from overwriting its successor. Each provider attempt
has the existing 10-second timeout, at most three total attempts with exponential
backoff/jitter, and the existing circuit breaker. Failed jobs retry later, from
one minute up to an hourly cap. A crash leaves an expiring, reclaimable lease.
All 96 crop/month rows publish atomically. Missing values or incomplete dates
never become zero risk. `/outlook` performs an indexed cache read and no HTTP call;
unavailable weather does not disable existing price data.

## Data and period

[Open-Meteo Historical Weather API](https://open-meteo.com/en/docs/historical-weather-api)
is requested with `models=era5`, daily minimum/maximum 2m temperature in Celsius,
precipitation in millimetres, and `timezone=Africa/Johannesburg`. A consistent
reanalysis model avoids mixing the default model products over the period.
The 0.1-degree application cache is **not** a claim of 0.1-degree ERA5 resolution;
ERA5's native grid is approximately 0.25 degrees. Reanalysis estimates are not
measurements from a weather station on the farm. Open-Meteo/Copernicus attribution
must accompany presentation; check the provider's commercial service terms
before commercial deployment (the public endpoint is non-commercial).

Use the latest fifteen complete planting years, including the following year's
daily observations for December crops that mature after New Year. The longest
December window must have ended at least seven days ago (a buffer beyond ERA5's
five-day publication delay). This is not a partially observed trailing interval:
on 2026-01-01 it uses 2010–2024 plantings; on 2026-09-23 it uses 2011–2025
plantings with observations through 2026-07-28. Output includes the actual
planting-year range, 15-year denominator,
computation time and SHA-256 of the normalized provider JSON. Changes in policy
or calendar year require new results, never silent relabelling of old rows.

## Policy and limitations

`weather_policy.py` hashes all policy inputs. Planting is assumed on the first day
of each month; each window contains exactly `growing_days` days, starting there.
The window is independent of the forecast snapshot's harvest assumptions and is
returned explicitly; it must not be presented as a validated harvest date.

The following screening windows use upper-end durations in the government's
[GDARD Vegetable Production Guidelines](https://www.nda.gov.za/images/how-to-start/home-gardening/vegetable-production-guidelines-gdard.pdf):

| Crop        | Days | Source/interpretation                                         |
| ----------- | ---: | ------------------------------------------------------------- |
| Butternut   |  170 | Page 1, combined pumpkin/butternut guidance; direct sowing    |
| Cabbage     |  120 | Page 3, field transplant to harvest                           |
| Carrots     |  105 | Page 4, direct sowing                                         |
| Onions      |  240 | Page 4, field planting; nursery time excluded                 |
| Potatoes    |  150 | Page 4, planted tubers                                        |
| Spinach     |   90 | Page 3; the named cultivars are Swiss chard, not true spinach |
| Tomatoes    |   90 | Page 1, field transplant to first harvest                     |
| Green beans |   85 | KZN guidance's early-spring example, below                    |

[KZN DARD, Length of Growing Period](https://www.kzndard.gov.za/images/Documents/Horticulture/Veg_prod/length_of_growing_period.pdf),
page 2, explains that a green bean crop taking 60 days in summer may need 85 days
in early spring. These guides describe variable cultivar/season durations, not
locally calibrated constants. The application deliberately reports its fixed
screening window. Repeated harvests, nurseries, irrigation and growth stages are
not modelled. Confirm the spinach/chard identity and local cultivar assumptions
with an agronomist before using this as individualized planting advice.

An event year is one with **at least one** qualifying event anywhere in the
growing window. Its share is event years / 15, not affected days / all days:

- Frost exposure: daily minimum temperature **below 0°C**.
- Potential heat-stress exposure: daily maximum **at least 35°C**.
- Dry spell: **at least seven consecutive days**, each with rain **below 1 mm**.

These are transparent **project screening definitions**, not damage thresholds
endorsed by the crop guides. All crops share these event definitions; their
windows differ. The 35°C and seven-day choices require agronomic validation
before being used to rank crop suitability. Rainfall-only dry spells do not
establish soil drought or account for irrigation. `warning`, `thresholds`,
`growing_days`, event-year counts and shares accompany every available response.
Do not replace this warning with “safe to plant” or use a zero share as a guarantee.

## Deployment and verification

Apply additive Alembic revision `0008` before starting the updated API/worker.
No existing table/data is rewritten and no cloud resources are created here.
Save a section with a supported boundary to queue it. Fresh demo seeds use a
clearly fictional coarse Hammanskraal-area point and queue the shared cell.
Repeated seeds queue existing demo boundaries without overwriting user edits.
Existing sections without location are unchanged. A bounded startup/hourly scan
queues existing active sections and catches annual/policy rollover without user
edits. Scans process 100 sections per iteration and interleave with jobs; they
never overwrite section records or compute unrequested country-wide cells.

Run `pytest apps/backend/tests/test_weather.py` and the forecast, sync and provider
regression suites. PostgreSQL tests exercise concurrent grid deduplication,
exclusive claims, rollback and migration compatibility. Fake-provider tests do
not establish live-provider availability or agronomic validity. Keep #21 open
until its remaining forecast, operational and performance acceptance is evidenced.
