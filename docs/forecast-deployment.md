# Forecast deployment and nightly acceptance

This wiring is part of #21. It does not provision secret values, enable a data
mode, apply Terraform, deploy to Google Cloud, or establish live acceptance on
its own. Keep #21 open pending reviewed forecast data and real staging evidence.

## Post-migration import

The existing trusted `main` deployment runs, in order:

1. Build the API image, back up Cloud SQL, and complete migrations.
2. Run `infra/gcp-forecast-import.sh`.
3. Deploy and verify the API, then promote traffic using the existing rollout.

`FORECAST_DATA_MODE` defaults to `disabled`: no import job or artifact build runs.
When explicitly set to `sample` or `historical`, the wrapper builds the separate
`forecast-import` Docker target, tagged with the exact deployment SHA. That image
contains only reviewed `ml/forecast/results/<run_id>/forecast.json` snapshots;
synthetic fixtures are **not** automatically shipped. API/worker images still do
not contain results or fixtures. Import/API modes use the same protected variable.
Do not enable historical mode with synthetic data, or describe month-number v1
snapshots as dated/live forecasts.

A bounded Cloud Run job invokes the existing ORM importer after migrations. Its
validation, immutable run IDs, idempotency, atomic activation, and rollback rules
remain unchanged. Rejected runs remain staged and the previous active run remains
active. The existing notifier opens/deduplicates an issue containing only the run
ID and allowlisted check names. Failure to notify also emits a fixed warning.

Build/push/job-configuration/job-execution failures emit a workflow warning and
return success so rollout may continue. A successfully completed job is not a
claim that every artifact was accepted: inspect its validation/notification logs.
There is no automatic retry of the import job. Infrastructure failures before a
run can be identified produce a workflow warning, not a fabricated per-run issue.
If a job loses connectivity after committing a validated run, the new run may
already be active; inspect state rather than assuming the old run is active.
The job has a 300-second limit; the caller waits up to 330 seconds. Source-build,
push and job-configuration calls are bounded separately.

Migration failures remain fatal and never reach the import/rollout steps. Failed
imports are not allowed to hide failed migrations. No CI gate is relaxed.

## Operator setup

After independent infrastructure review, apply `infra/forecast-import.tf` with the
existing Terraform configuration. It adds a forecast-import service account,
Cloud SQL connection permission, access to the database secret, and its own
Secret Manager container. It does not store a token value in Terraform state.

Set protected `staging` variables:

| Variable                           | Value                                              |
| ---------------------------------- | -------------------------------------------------- |
| `FORECAST_DATA_MODE`               | `sample` or `historical`, deliberately selected    |
| `GCP_FORECAST_IMPORT_ACCOUNT`      | Terraform `forecast_import_service_account` output |
| `GCP_FORECAST_GITHUB_TOKEN_SECRET` | Terraform `forecast_github_token_secret` output    |

Provision the latter container's enabled `latest` version out of band with a
repository-scoped fine-grained GitHub token granting Issues read/write only to
Farmable. Manage expiration/rotation explicitly. A short-lived installation token
also works only if an operator-managed mechanism refreshes it before the job;
this implementation does not mint installation tokens.

The secret is injected only into the import job. The API/worker service account
has no access to this new container, and GitHub Actions handles its resource name,
not its value. Existing migration and API identities receive no issue-writing
credential. No GitHub workflow token privileges are increased. The importer uses
the existing database credential; database-level table grants are unchanged.

Have at least one reviewed, mode-compatible results folder before enabling the
feature. An empty directory imports nothing; the nightly check must fail until an
active snapshot actually exists. Never copy fixtures into results automatically.

## Nightly authenticated HTTP check

The actual `nightly-staging.yml` now runs `gcp-outlook-smoke.sh` after its live
revision/health checks. It shares deployment's concurrency group so those two
workflows cannot change the smoke job or active forecast simultaneously. Manual
database operations must also be coordinated with the acceptance run.

The job runs `python -m farmable_backend.outlook_smoke` from the `backend:<SHA>`
image corresponding to the serving revision, **not the latest branch head**.
Keep SHA-tagged images immutable operationally; this change does not enforce a
registry tag-immutability policy. The smoke job receives only the database secret,
not the issue-writing token. It has no retry and a 180-second task deadline.

Requirements: deploy this code, enable forecasts, import a reviewed snapshot, and
prepare the existing fictional demo farm. Its fixed demo owner must already have
an `AuthIdentity` with phone and email verified through an operator-approved setup.
`seed-demo` alone does not create that verified identity. The smoke command never
creates/verifies identities, changes farm records or imports sample data.

The checker refuses non-staging environments, non-HTTPS/non-Cloud-Run URLs, or a
disabled forecast mode. It verifies the serving SHA and unauthenticated denial,
then checks demo-farm ownership through the ORM. It creates a random three-minute
session for **only that fixed demo owner**, calls the normal HTTP `/outlook` route
for all eight crops and twelve planting months, and removes its session in a
`finally` block. No authentication route or ownership check is bypassed. The job
does mint a trusted operator session, so its database access must remain restricted;
this is not an end-to-end OTP/login test. It does not expose a refresh token.
If killed before cleanup, the session expires after three minutes.

Requests have a five-second maximum timeout, a 120-second overall work budget and
a 64-KiB decoded response bound, with no redirects or environment proxies. Output
is fixed pass/fail text plus the successful check count; credentials and farm
responses are never printed. Positive finite prices/costs/yields, ordered ranges,
crop/month identity, consistent run, data-kind/sample warning, response schema and
no-store policy are checked. Weather `unavailable` remains a valid graceful fallback,
not zero risk. The check does not prove source accuracy, forecast freshness, weather
calibration or production latency.

Missing setup or data, malformed responses, API failure, ownership
failure or failed cleanup makes the nightly job fail; it is not silently skipped.
Capture the actual staging workflow URL and `PASS: outlook present for all demo
crops (96 crop/month checks)` before claiming live acceptance. Local fake-provider
and SQLite tests do not establish that evidence.
