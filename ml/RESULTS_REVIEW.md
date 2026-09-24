# Issue 20 real-result review

**Run ID:** `5310d438e67b5333c22786a9b727f8c78fda671314677af9f77c59d131bd952d`

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
- The runner generated two independent output roots with the same run ID. All ten
  files across the forecast and backtest result folders are byte identical. Both
  copies of `manifest.json` agree, and every listed artifact hash matches its file.
- `ml/forecast/validate_output.py` accepts the 96-row, constant-2025-rand
  `forecasts.parquet`. The backend consumer accepts `forecast.json` in explicit
  `retrospective` mode and rejects it in `historical` mode. Gitleaks found no secrets
  in either result folder.
- A backend test imports the committed real `forecast.json` through the ORM into a
  disposable database, confirms an identical second import is idempotent, and
  serves an authenticated outlook with the retrospective warning. No production
  database was changed.

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

The result is a retrospective fixed-2025-input simulation using current-vintage
Joburg Market history, current-vintage CPI and frozen Western Cape production
assumptions. It does not establish historical publication availability or observed
farmer income. The 2025 deployment snapshot is separate from the historical
decision ledger and follows protocol Amendment 1's frozen seasonal ranges.

## Remaining acceptance work

An independent reviewer should inspect the numeric artifacts and the no-switch
tomato case. The notebook still needs a credential-free Colab execution and
cross-environment artifact comparison. The real snapshot has been imported only
into a disposable test database. After the results PR merges,
rerun the default protocol history gate to confirm the first committed result
follows the independently merged protocol. Issue #20 cannot use its requested
eight-default slide sentence unless a future, separately registered evaluation
actually yields defined switch statistics for every default.
