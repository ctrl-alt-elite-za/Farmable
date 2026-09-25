# Issue 20 real-result review

**Run ID:** `c67c0ad8d791c19ad711a8aeaf90a8dad26e60b5bec127c75fe422f63f78429f`

**Status:** reproducible retrospective result for review; issue #20 is not complete.
The registered eight-default headline sentence is unavailable.

## Provenance and repeat

- PR #77 merged the original protocol before any real result. PR #83 merged dated
  Amendment 1 before this complete run. The first attempt under the unamended
  snapshot implementation stopped before writing artifacts; no decision scores
  were inspected.
- All 17 original 2008–2024 market workbooks in ignored local storage matched the
  committed filename, byte length and SHA-256 audit. Raw workbooks are not in the
  results PR. The runner consumed 1,632 monthly crop-price observations.
- The published result uses the LF source bytes committed in Git. The first
  Windows run used CRLF working-tree bytes for `market_workbook_audit.json`
  (SHA-256 `461cf7c8c33db22d34163f835abe58de3c2699864486878cda6556d545fa6386`),
  while Git and Colab use LF bytes (SHA-256
  `0dc4a4e596bcd05614a6012104eebaf8d836bda06581d40a883977874023afb2`).
  The Windows-provenance artifact folders were removed from this PR. The current
  run ID is the one produced by Colab from the committed inputs. Both copies of
  `manifest.json` agree, and every listed artifact hash matches its file. Two
  local regeneration roots using the committed Git inputs and the Colab run's
  recorded Python 3.12.3/Linux identity produced the same run ID and all ten
  output files byte for byte.
- `ml/forecast/validate_output.py` accepts the 96-row, constant-2025-rand
  `forecasts.parquet`. The backend consumer accepts `forecast.json` in explicit
  `retrospective` mode and rejects it in `historical` mode. Gitleaks found no secrets
  in either result folder.
- A backend test imports the committed real `forecast.json` through the ORM into a
  disposable database, confirms an identical second import is idempotent, and
  serves an authenticated outlook with the retrospective warning. No production
  database was changed.
- The committed notebook ran in a fresh Google Colab runtime at PR revision
  `26c5a3213642a30759bf48bc50e4b8f84f823217` with all 17 audited workbooks.
  Its dependency install, ML tests, protocol readiness check, real runner and
  96-row Parquet validator passed. Colab produced the published run ID. The
  decision ledger, rendered table, slide sentence and forecast ledger match
  the earlier Windows artifacts byte for byte; report numeric results match.

## What the decision ledger shows

The report covers the complete January 2012–December 2024 grid: eight defaults
times 156 planting months, or 1,248 keys. Of these, 702 are out of season, 84 lack
a forecast, 18 lack a realized harvest price and 444 are scorable. There are 326
switches, with 316 positive gains. These counts were recomputed directly from
`decision_ledger.parquet` and agree with `decision_backtest.json`.

For tomatoes, all 42 scorable rows recommend tomatoes, so there are **zero
switches**. Its switch win rate, gain distribution and interval are undefined.
`slide_sentence.txt` correctly contains `INSUFFICIENT EVIDENCE` rather than a
sentence implying a measured switch outcome for every default. The pooled numbers
and the full per-default table remain in the result artifacts for audit; **do not
use the pooled figure alone as the registered eight-crop pitch statistic**.

The strong pooled gains depend heavily on the tomato assumption. Of 326
switches, **174 recommend tomatoes**, and all 174 show a positive gain; the
other 152 recommend cabbage, with 142 positive gains. The frozen 2025 snapshot
has a median predicted P50 margin of about R138,000/ha/month for tomatoes,
compared with about R34,000 for cabbage and R33,000 for carrots, using the
registered crop-specific marketing rates. Tomatoes top all 12 snapshot months
before calendar eligibility; the historical recommendation ledger still chooses
cabbage for 152 switches. The registered processing-tomato budget uses
62.5 t/ha with **0% marketing**, as in the source budget, while the prices are
from the fresh-produce market. Even applying a hypothetical 12.5% marketing fee
to tomatoes leaves a median snapshot margin near R114,000/ha/month. This
incompatible input pairing, rather than demonstrated forecasting skill,
plausibly drives the 100% tomato-switch win rate and much of the pooled gain.
**Do not quote any per-default or pooled gain figure as evidence of farmer
benefit** until tomato inputs are corrected or tomatoes are excluded under a
separately registered evaluation.

The result is a retrospective fixed-2025-input simulation using current-vintage
Joburg Market history, current-vintage CPI and frozen Western Cape production
assumptions. It does not establish historical publication availability or observed
farmer income. The 2025 deployment snapshot is separate from the historical
decision ledger and follows protocol Amendment 1's frozen seasonal ranges.

## Remaining acceptance work

Code owner change requests on provenance, tomato interpretation and a backend
test assertion are being addressed. The real snapshot has been imported only
into a disposable test database. After the results PR merges, rerun the default protocol history gate
to confirm the first committed result follows the independently merged protocol.
Issue #20 cannot use its requested
eight-default slide sentence unless a future, separately registered evaluation
actually yields defined switch statistics for every default.
