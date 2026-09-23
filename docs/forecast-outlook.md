# Fixture-backed crop outlook (#21)

This slice removes the **development** dependency on #20, not the need for honest
forecast evidence. It implements the import → validation → activation → authenticated
outlook → rollback path using a committed synthetic snapshot. No public market data
has been analysed and no model has been trained by this snapshot path.
Location-triggered weather exposure is implemented separately; see
[weather-risk.md](weather-risk.md) for its policy, warnings and operational limits.
Keep #20 and #21 open until their remaining acceptance criteria are met.

## Scope and merge order

The branch is stacked on PR #56 solely to keep Alembic revisions sequential:
`0005 → 0006 (voice quota) → 0007 (forecast snapshots)`. Voice may remain disabled.
Review this PR's forecast-only diff, merge/rebase after #56, and do not create
parallel Alembic heads. Migration approval remains a maintainer decision; this
change does not relax CI, add approval labels, or deploy anything.

## Run the sample-backed path

Use a local/disposable database and the existing backend setup. Run from the
repository root. `DATABASE_URL` must already be configured; do not print secrets.

```sh
make db-migrate
export FORECAST_DATA_MODE=sample
make forecast-import-latest FORECAST_DIR=ml/forecast/fixtures
# Start/restart the backend with the same FORECAST_DATA_MODE=sample environment.
```

The normal default directory is `ml/forecast/results`, **not** the fixture directory.
`FORECAST_DATA_MODE=disabled` is the default and imports nothing. Import is explicit,
not an API startup side effect, and it does not create users or farms. Use a verified
Farmable access session and an existing section owned by that user (the existing
auth and farm seed flows are separate).

Call `GET /outlook?section_id=<UUID>&crop=cabbage&plant_month=1` with the normal
`Authorization: Bearer <Farmable access token>`. The generated API client exposes
`getCropOutlook`. No extra/duplicate query parameters or caller-supplied provider
configuration are accepted. Other users' sections and deleted sections/farms return
`404`; an invalid session returns `401`.

The snapshot includes:

- `run_id`, `forecast_as_of`, `data_kind`, and `warning` (mandatory sample warning
  text when synthetic). Display the warning next to the figures, not only in a tooltip.
- `crop`, `plant_month`, `harvest_month`, `method`, and `price_range` with P10/P50/P90
  in `ZAR/kg`, **for harvest after the selected planting month**.
- `cost_per_ha`, `yield_kg_per_ha`, `break_even_price_per_kg`, `currency=ZAR`,
  `price_basis_year=2025`, and the source assumptions.
- `weather_risk.status=unavailable` with `climatology_not_computed` until a matching
  weather cache exists, or `available` with labelled historical exposure shares.
  Never display unavailable as zero risk or interpret exposure as crop suitability.

Decimals are JSON strings, consistent with other backend Decimal DTOs. The fixture's
January cabbage example gives `p50=5.0000`, cost `75000.0000`/ha, assumed yield
`20000.0000` kg/ha, and break-even `3.7500`/kg. These are invented inputs, not advice.
No margin or yield guarantee is returned. Area-based totals belong to the planner.

This normalized v1 contract indexes the twelve **planting-month numbers**, not a
particular future year. It must not be presented as a dated/live forecast. A future
production horizon change requires an explicit contract version, not silent reuse.
`forecast_as_of` is the snapshot's data timestamp, not evidence it is still current.

`503 forecast_disabled`, `forecast_unavailable`, or `forecast_mode_mismatch` means
the client must show an unavailable outlook rather than inventing numbers. The
endpoint uses no provider calls and returns `Cache-Control: no-store`.

## Artifact contract and validation

Each run folder contains one bounded (at most 1 MiB) `forecast.json`, modelled by
`ForecastBundle` in `forecast_contract.py`. `ml/forecast/fixtures/sample-v1` is a
complete example with eight crops × twelve planting months. It is deliberately
outside `results/`, and its source file/hash and invented arithmetic are committed.

Metadata: `schema_version=1`, immutable `run_id` matching the folder, `data_kind`
(`synthetic` or `historical`), timezone-aware `as_of`, `currency=ZAR`,
`price_basis_year=2025`, source names/SHA-256 hashes, and assumptions. Source hashes
record provenance claims; validating their shape is **not** an independent audit
of external data, CPI conversion, backtests, or model accuracy.

Each row has `crop`, `plant_month`, `growing_months`, `p10`, `p50`, `p90`, `method`,
positive `cost_per_ha`, and positive `yield_kg_per_ha`. The consumer computes harvest
month with year wrap and break-even as cost/yield, rounded to four decimal places.
Supported crop IDs: `butternut`, `cabbage`, `carrots`, `green_beans`, `onions`,
`potatoes`, `spinach`, `tomatoes`. Beetroot and pumpkins are excluded.

The importer checks strict schema, finite decimal precision, exactly one of every
crop/month, positive prices, ordered quantiles, compatible data mode/method,
duplicate source names, no future timestamp, no automatic older-as-of replacement,
and P50 movement **no greater than 50%** against the active run of the same kind.
Historical results must not use `method=fixture`. Synthetic values never serve as
the historical-price baseline when explicitly switching to historical mode.

Successful imports atomically supersede the old run and activate the new one.
Invalid parsed artifacts stay `staged`, with fixed check names, without changing
the active pointer. Completely malformed JSON is also staged, without storing its
raw contents. Missing/oversized/unsafe files are reported as rejected and never read
unboundedly. Symlinks/path escapes are refused; discovery is capped at 256 folders.

Run IDs and source bytes are immutable: identical imports are idempotent, and changed
bytes under an existing ID are rejected. Correct a staged artifact in a **new run
folder**, not by silently replacing its content. Runs are scanned in folder-name
order; an older `as_of` encountered after a newer active run remains staged.

```sh
make forecast-activate RUN=sample-v1
```

Rollback only accepts a previously active, mode-compatible run. It cannot override
failed quality checks on a staged run. Re-importing a superseded snapshot never
undoes rollback. Concurrent importers/rollbacks lock the singleton state row; a
partial unique index also prevents multiple active runs. Readers obtain the active
snapshot in one query and do not depend on an application-process cache.

Import failures emit fixed warning codes and return exit 0 so an operator/deploy
can retain the last active snapshot; rollback failures return nonzero. Failed runs
persist their check names. The CLI can report failures to GitHub using the opt-in
configuration below. Deployment wiring is still separate; a console warning is
not proof that an issue was created.

## GitHub failure reporting (import job only)

The CLI uses GitHub's [repository issues API](https://docs.github.com/en/rest/issues/issues).
Inject these variables into the **trusted import job only**, from the deployment
secret store; do not add them to the shared API/worker environment or mobile app:

- `FORECAST_GITHUB_ENABLED=true`
- `FORECAST_GITHUB_REPOSITORY=ctrl-alt-elite-za/Farmable`
- `FORECAST_GITHUB_TOKEN`: a short-lived GitHub App installation token, or a
  repository-scoped fine-grained token, with Issues read/write on this repository.

This does not grant workflow permissions, configure cloud secrets, deploy, or make
real GitHub requests during tests. Never expose an issue-writing credential to
untrusted PR code. Notifications default off. Failed imports then print
`notification_disabled` alongside the actual failed checks.

Each report contains only the validated run ID and allowlisted check names, with
a run-ID marker for deduplication. Raw data, provider errors, paths and secrets are
excluded. Repeated imports reuse an existing report, including renamed or closed
issues whose marker remains. They do not reopen it or replace its original checks.
Keep the marker intact; removing it or deleting the issue permits a new report.

Cooperating importers using the same database serialize lookup/create using the
existing forecast-state row lock, **after** each import transaction commits.
Ordinary outlook reads do not take that lock. Notification can temporarily delay
other imports/rollbacks; their database statement timeout still applies. Different
databases targeting the same repository are not covered by this serialization;
use a single notification-writing import job per repository. No new migration is
required.

Lookup includes open and closed issues and excludes PRs, with at most ten pages
of 100 records, 1 MiB per response, five-second HTTP phase timeouts and a 20-second
processing budget checked before requests and as response chunks arrive. An
in-flight HTTP operation can extend beyond that processing budget until its phase
timeout. If lookup is incomplete, reporting fails closed instead of risking a
duplicate. Repositories exceeding the scan limit require a reporting-index change;
do not remove the limit silently. No redirects or environment proxies are followed.

POST is never automatically retried: GitHub might have accepted it before a
connection failed. The next import looks up the marker again. GitHub does not
provide a transactional exactly-once guarantee with our database. Transient
visibility gaps can still cause duplicates after an ambiguous request.

Any notification/configuration failure prints only `notification_failed`; it does
not roll back activation, stop processing other folders or fail deployment.
Unresolved staged artifacts are retried for notification on subsequent imports;
there is no background delivery queue. A command-level failure (such as an
unreachable database or invalid root) remains a console warning, since no safe
per-run notification transaction can be established.

## Seeded PostgreSQL performance check

`make test-integration` explicitly runs `e2e/perf/test_outlook.py` in the disposable
Compose project. The shared fixture refuses non-CI environments, migrates a random
schema, and removes that schema on exit. No developer or production farm is used.

The benchmark adds 100 farms and 1,000 sections to the normal ownership/auth seed,
imports the synthetic snapshot, warms eight requests, then measures all 96
crop/planting-month lookups through the real authenticated ASGI route against
PostgreSQL. It asserts every response, retains the sample warning, reports
nearest-rank p95, and fails at 200 ms or above. The normal rate limiter stays on.
Measurement includes authentication, database access and response serialization;
it excludes network/proxy latency, live weather, concurrency and production load.
Do not present it as deployed latency or the staging rehearsal. CI logs print the
sample count, workload and measured p95. Docker must be running to obtain a result.

## Verification and remaining work

Unit tests exercise all 96 crop/month lookups, ownership/authentication, mode
separation, real arithmetic, strict validation, no provider calls, idempotency,
atomic failed imports, rollback, safe warnings, and migration/ORM agreement.
The disposable PostgreSQL integration suite exercises concurrent initial imports,
same-ID races, rollback, and schema-qualified migration round trips.

Still required for full #21:

1. Agree the production artifact/horizon contract with #20; add its
   `forecasts.parquet`/manifest conversion. This JSON contract is a normalized
   fixture seam, **not a claim to read the Parquet format already specified in #20**.
2. Verify real price, cost, yield and CPI sources and consume reviewed #20 output.
   A historical-range baseline can be built independently; publishing simulation
   results still requires the protocol-first process, with no invented statistics.
3. Validate the weather screening policy agronomically and verify real-provider
   operation in the deployment; the queue, calculation, cache and unavailable
   fallback are documented in [weather-risk.md](weather-risk.md).
4. Configure and verify the opt-in GitHub notifier in the trusted import job and
   wire the after-migration deployment step. No deployment permissions are changed here.
5. Obtain passing evidence from the seeded PostgreSQL performance check and add
   the all-demo-crops check to the actual staging rehearsal. Unit timing is not
   evidence for production latency.
