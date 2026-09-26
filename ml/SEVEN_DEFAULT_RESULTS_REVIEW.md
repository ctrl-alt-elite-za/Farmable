# Issue 20 Amendment 2 result review

**Status:** locally reproduced and validated; awaiting amended Colab execution,
independent result review and PR acceptance. Issue #20 is not yet complete.

**Run ID:** `69dbbedc531c3d1baf8349e0b9936dc9fb17aa702d84895d31594d6a12c9b2f7`

## Registered scope and provenance

Protocol-only PR #100 merged as `da7653ba00dd18ab480b4ca5dbf27a058b49b5d2`
before this run. The runner verified the exact merged protocol against
`origin/main`; all 17 original market workbooks passed the committed hash audit.
The implementation is PR #102 revision `3d959eb55bda43d5dfa2cead2fe092116bbaa4d3`
plus reporting fix `0c180d6`, which names the seven starting crops even when switch
statistics are undefined. No input, forecast, recommendation, metric or protocol
rule was changed after examining the amended result.

Two preliminary local executions of that reviewed revision produced run
`9036ea089ef339e596311ca2d078495f04d8fa639b5da6c5c0b9b72569fedfe4`.
The fallback sentence omitted the issue's required words "7 starting crops".
After fixing and testing that disclosure, two new process executions produced
the published run above and ten byte-identical files. The preliminary runs remain
local scratch outputs; their numerical results are unchanged by the wording fix.

The manifests record exact code, protocol, input and archived comparison hashes.
The runtime is Python 3.12.11 on Windows, LightGBM 4.7.0, NumPy 2.5.3,
PyArrow 25.0.1, xlrd 2.0.2 and openpyxl 3.1.5. Runtime identity contributes to
the run ID: a Colab/Linux repeat must retain its actual identity, and may have a
different run ID. Cross-platform byte equality is not claimed.

## Results and limits

The January 2012–December 2024 grid contains seven defaults × 156 months =
1,092 keys. There are 400 scorable decisions, 283 switches and 117 no-switches.
The 692 explicit skips comprise 598 out-of-season defaults, 76 missing forecasts
and 18 missing realized prices. Tomatoes occur in neither decision defaults nor
recommendations. Beetroot and pumpkins retain their missing-budget exclusions.

Cabbage has 75 scorable decisions and zero switches. Its switch statistics are
undefined, so the generated sentence correctly withholds the headline:

> INSUFFICIENT EVIDENCE: switch statistics are undefined for one or more of the 7 starting crops. Tomatoes excluded: no compatible reviewed fresh-market production budget. Amendment 2 was registered after the version 1 result was observed.

All required per-default and pooled metrics, including negative outcomes and
null reasons, are published in the report. They describe a retrospective
fixed-2025-input scenario, not historical publication availability, observed
farmer incomes or demonstrated forecast skill. The registered seven-default
headline is unavailable; pooled values must not be substituted for it.

The separate tomato artifact has exactly twelve 2025 calendar-target-month price
ranges from frozen pre-2025 observations. It contains no planting, yield, cost,
marketing or profit fields and is not a backend-importable forecast bundle.

## Artifacts

- [Seven-default table](backtest/results/69dbbedc531c3d1baf8349e0b9936dc9fb17aa702d84895d31594d6a12c9b2f7/decision_backtest.md)
- [Full JSON report](backtest/results/69dbbedc531c3d1baf8349e0b9936dc9fb17aa702d84895d31594d6a12c9b2f7/decision_backtest.json)
- [Side-by-side version comparison](backtest/results/69dbbedc531c3d1baf8349e0b9936dc9fb17aa702d84895d31594d6a12c9b2f7/version_comparison.md)
- [Provenance manifest](backtest/results/69dbbedc531c3d1baf8349e0b9936dc9fb17aa702d84895d31594d6a12c9b2f7/manifest.json)
- [Tomato prices only](forecast/price_only_results/69dbbedc531c3d1baf8349e0b9936dc9fb17aa702d84895d31594d6a12c9b2f7/tomato_price_forecasts.json)

The eight-default version 1 run and its 96-row snapshot remain byte-for-byte
unchanged. They are archived evidence and must not be represented as corrected
tomato advice. The comparison explicitly discloses the different crop universes;
changes in pooled gains cannot be attributed to improved model skill.

## Verification

- ML forecast/backtest/service and ORM reference-import tests: **173 passed**.
- Added committed-artifact regression: **1 passed**; CI now validates the actual
  published amended files as well as the synthetic runner outputs.
- Repository Ruff and changed-Python formatting checks pass. Mypy passes for
  all 24 ML adapter/test files and 21 ML implementation/vision files.
- Two independent local process runs: identical run IDs and all ten output files.
- Full amended-run validator and 12-row tomato price validator: pass.
- All manifest source hashes match the files used; unchanged inputs also match
  committed Git bytes. All archived version 1 artifact bytes match Git.
- Protocol history: pass, original protocol `73e2c6296a5a` precedes first results
  `87c903bd02cd`; the amended runner separately verifies Amendment 2's merge.
- Gitleaks `detect --source ml/ --config .gitleaks.toml --redact`: pass across
  370 commits. Full available history (`--all`) and working-tree scans of `ml/`
  and the ML implementation also pass with no leaks.
- Node lint and workspace type checks pass; geo tests: **120 passed**.
- Backend/scripts/migrations/E2E mypy: **220 files passed**; the no-raw-SQL guard
  passed across **181 files**.
- PR #102's reviewed implementation has passing Linux lint, typecheck, unit,
  integration, security, migration, deployment and E2E checks. These are previous
  implementation evidence, not a substitute for checks on this results commit.

## Remaining acceptance requirements

1. Run `ml/notebooks/seven_default_backtest.ipynb` at the exact published revision
   in Colab with the audited workbooks; retain its true runtime identity and
   compare decision/price values with this run. No browser provider is available
   in this execution session, so no amended Colab run is claimed.
2. Obtain independent review of the real amended artifacts and their comparison.
   PR #102's approvals reviewed implementation before these results existed.
3. Pass the results PR's required checks and merge through the normal review
   process, after PR #102. Native Make is unavailable here; no new successful
   complete `make lint`, `make typecheck` or `make test` run is claimed.
4. Re-run the protocol history gate on final mainline and verify Amendment 2
   precedes introduction of this distinct result directory before closing #20.
