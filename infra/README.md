# Google Cloud demo deployment

Issue #6 deploys the smallest online backend in `africa-south1`:

- Cloud Run runs the FastAPI image and its Procrastinate worker in one bounded
  demo instance so `/health/ready` can verify both heartbeats.
- Cloud SQL PostgreSQL 16 is the database. Cloud SQL supports the PostGIS
  extension used by the backend's existing schema.
- Artifact Registry stores immutable images tagged with the full commit SHA.
- Cloud Storage is uniform-access, versioned, and has public access prevention
  enforced. Live media is retained; noncurrent versions expire after 30 days.
  The deployment service account runs a private upload/download smoke.
- Secret Manager supplies `DATABASE_URL` and provider credentials to Cloud Run.
- GitHub Actions uses OIDC Workload Identity Federation; no service-account JSON
  key is stored in GitHub or the repository.

## Deployment runbook

Follow the phases in order. Do not skip ahead: each phase assumes the previous one
completed.

**Target environment for the hackathon demo**

|                    |                                                                  |
| ------------------ | ---------------------------------------------------------------- |
| Project            | `almanac-staging-za` (number `116072622336`)                     |
| Region             | `africa-south1` (Johannesburg)                                   |
| Billing account    | `01A497-80BCE2-105B5A`, with a $20/month budget already in place |
| Cloud SQL instance | `farmable-staging`                                               |
| Connection name    | `almanac-staging-za:africa-south1:farmable-staging`              |

**Terraform does not create the backend.** It builds the foundation only — registry,
database, bucket, empty secret containers, service accounts, OIDC identity. The Cloud
Run service and the migration job are created by the deploy workflow in Phase 5.
Nothing serves traffic until then.

### Phase 0 — already done, verify only

```bash
gcloud config get-value project     # almanac-staging-za
gcloud billing projects describe almanac-staging-za --format='value(billingEnabled)'
```

Anyone running Terraform needs `CLOUDSDK_CONFIG` pointing at the shared credential
directory, set in their own shell before authenticating:

```bash
gcloud auth login && gcloud auth application-default login
```

### Phase 1 — foundation (Terraform)

```bash
terraform -chdir=infra init
terraform -chdir=infra plan  -var=project_id=almanac-staging-za
terraform -chdir=infra apply -var=project_id=almanac-staging-za
```

Expect **58 to add, 0 to change, 0 to destroy**. If the plan reports destroys, stop and
escalate — a clean project has nothing to destroy.

Then capture the outputs; Phase 4 needs them:

```bash
terraform -chdir=infra output
```

### Phase 2 — database password and PostGIS

Terraform deliberately creates no database user, so no password ever passes through this
repository. Set one on the built-in `postgres` user:

```bash
gcloud sql users set-password postgres \
  --instance=farmable-staging --project=almanac-staging-za --prompt-for-password
```

Then enable PostGIS once on the `farmable` database. The migrations do not run
handwritten SQL, so this stays outside Alembic:

```bash
gcloud sql connect farmable-staging --user=postgres --project=almanac-staging-za
```

```sql
\c farmable
CREATE EXTENSION postgis;
```

`gcloud sql connect` needs a local `psql`. Without one, use Cloud Shell in the browser.

### Phase 3 — secret values

Provider keys are read by the **backend**, never shipped in the mobile app, so every key
the app needs must exist here. Add each value out of band — never in a GitHub variable,
a workflow argument, or a file in this repository:

```bash
printf '%s' 'THE_VALUE' | gcloud secrets versions add farmable-staging-gemini-api-key \
  --project=almanac-staging-za --data-file=-
```

**Required before the first deploy** (the service will not start without them):

| Secret                            | Notes                          |
| --------------------------------- | ------------------------------ |
| `farmable-staging-database-url`   | see format below               |
| `farmable-staging-gemini-api-key` | the demo's primary integration |

**Optional** — the rollout wires each one only if it holds an enabled version, and skips
it otherwise. A skipped provider reports unavailable; it does not break the deploy, so
keys can be added later followed by a redeploy:

`gemini-model`, `twilio-account-sid`, `twilio-verify-service-sid`, `twilio-auth-token`,
`turnstile-secret`, `turnstile-hostname`, `azure-speech-key`, `azure-speech-resource`,
`azure-speech-region`, `crop-health-api-key`, `maps-server-api-key` — each prefixed
`farmable-staging-`.

Do **not** add placeholder values. Several fields are pattern-validated
(`TWILIO_ACCOUNT_SID` must match `^AC[0-9a-fA-F]{32}$`), and a value that fails
validation crashes the container on startup. Leave a secret empty of versions instead.

The database URL must use the `postgresql+psycopg` driver and reach Cloud SQL over the
Unix socket the Cloud Run connector mounts:

```
postgresql+psycopg://postgres:PASSWORD@/farmable?host=/cloudsql/almanac-staging-za:africa-south1:farmable-staging
```

### Phase 4 — GitHub `staging` environment variables

Create a `staging` environment on the repository and add these as variables. All are
non-secret resource identifiers:

| Variable                         | Value                                                                         |
| -------------------------------- | ----------------------------------------------------------------------------- |
| `GCP_PROJECT_ID`                 | `almanac-staging-za`                                                          |
| `GCP_WORKLOAD_IDENTITY_PROVIDER` | Terraform output `workload_identity_provider`                                 |
| `GCP_DEPLOYER_SERVICE_ACCOUNT`   | `farmable-staging-deployer@almanac-staging-za.iam.gserviceaccount.com`        |
| `GCP_RUNTIME_SERVICE_ACCOUNT`    | `farmable-staging-runtime@almanac-staging-za.iam.gserviceaccount.com`         |
| `GCP_ARTIFACT_REPOSITORY`        | `africa-south1-docker.pkg.dev/almanac-staging-za/farmable-staging-containers` |
| `GCP_CLOUD_SQL_INSTANCE`         | `farmable-staging`                                                            |
| `GCP_CLOUD_SQL_CONNECTION`       | `almanac-staging-za:africa-south1:farmable-staging`                           |
| `GCP_MEDIA_BUCKET`               | `almanac-staging-za-farmable-staging-media`                                   |
| `GCP_DATABASE_SECRET`            | `farmable-staging-database-url`                                               |
| `GCP_GEMINI_SECRET`              | `farmable-staging-gemini-api-key`                                             |

Optional overrides: `INTEGRATIONS_MODE` (defaults to `live`) and `GCP_SECRET_PREFIX`
(defaults to the prefix implied by `GCP_DATABASE_SECRET`).

**The forecast import lane is separate and off by default.** `FORECAST_DATA_MODE`
defaults to `disabled`, so no import job or artifact build runs and the demo does not
need it. To enable it you also need `GCP_FORECAST_IMPORT_ACCOUNT` and
`GCP_FORECAST_GITHUB_TOKEN_SECRET` (Terraform outputs `forecast_import_service_account`
and `forecast_github_token_secret`), plus a value in
`farmable-staging-forecast-github-token`. That lane has its own runbook — see
[forecast deployment](../docs/forecast-deployment.md) — and it is not duplicated here so
the two cannot drift apart.

### Phase 5 — first deploy

Run the **Deploy demo backend** workflow from the `main` branch. It must be `main`: the
OIDC provider pins `assertion.ref == 'refs/heads/main'`, so a dispatch from any other
branch fails at authentication.

The run builds the image, completes and verifies a Cloud SQL backup, migrates, creates a
no-traffic revision, checks readiness, runs three smokes, and only then routes traffic.

### Phase 6 — verify

```bash
gcloud run services list --project=almanac-staging-za --region=africa-south1
curl -s "$(gcloud run services describe farmable-backend --project=almanac-staging-za \
  --region=africa-south1 --format='value(status.url)')/health/ready"
```

`/health/ready` must report `database: ok` and `worker: ok` with the deployed commit SHA.
Also check the deploy log's `Provider secrets wired:` line to confirm the integrations
you expect are actually attached — names only are printed, never values.

### Before the event

Set `DEPLOY_FREEZE=on` as a repository variable. The deploy job is skipped before
authentication, image push, backup, migration, or traffic changes. Remove it afterwards.

It must be repository-scoped, not environment-scoped: both jobs gate on it from a
job-level `if:`, which GitHub evaluates before a job's environment is resolved, and the
`frozen` job declares no environment at all. An environment-scoped variable would be
invisible to both and the freeze would silently fail open.

### Troubleshooting

| Symptom                                          | Cause                                                                                                                           |
| ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------- |
| Revision fails to start, no application logs     | A referenced secret holds no enabled version, or a value fails pattern validation. Check the `Provider secrets wired:` line.    |
| Workflow fails at the auth step                  | Dispatched from a branch other than `main`; the OIDC provider pins `refs/heads/main`.                                           |
| Readiness reports `worker: down`                 | The worker cannot reach the database. Check `DATABASE_URL` uses `postgresql+psycopg` and the `/cloudsql/...` socket host.       |
| `terraform destroy` fails                        | `deletion_protection` on Cloud SQL and `force_destroy` on the bucket. See the kill switch below.                                |
| `terraform apply` rejects the Cloud SQL instance | An `sql.restrictPublicIp` organization policy. Not set on this org; a company org would need private IP plus Direct VPC egress. |
| `--allow-unauthenticated` refused                | Domain-restricted sharing blocks `allUsers`. Use `--no-invoker-iam-check`. Not applicable on this org.                          |

6. Set a Cloud Billing budget on the project before the first deploy, with
   email alerts at 50%, 90% and 100% of actual spend. Google Cloud does not cap
   spend, so the alert is the only warning before the demo project overruns.

7. Once gcloud is authenticated, `terraform apply` has run, and the secret
   versions exist, run the read-only setup check:

   ```bash
   GCP_PROJECT=YOUR_PROJECT_ID GCS_BUCKET=YOUR_PROJECT_ID-farmable-staging-media \
     bash infra/gcp-verify-setup.sh
   ```

   It reports `PASS:` or `FAIL:` per check, reports all of them rather than
   stopping at the first, and creates nothing. The GitHub side is checked by
   `infra/gcp-required-config.sh`, the deploy workflow's first step, which names
   any variable from step 4 that is still unset and stops before authenticating,
   so a missing variable never costs an image build.

What to run and what to capture for each of issue #6's acceptance criteria — a
real deploy, a freeze, a rollback, a backup before migration, the nightly run,
and the absence of any service-account key — is in
`docs/deploy-staging-acceptance.md`.

The nightly workflow resolves the service URL and expected commit SHA from the
single revision receiving 100 percent of live traffic. It does not rely on a
manually updated URL or SHA variable, and it fails if the live service,
database, worker, or revision identity is unhealthy.

## Delivery and failure behavior

Forecast import is a separate, bounded post-migration job. The nightly workflow
also verifies authenticated demo crop outlooks. Both require explicit operator
configuration; see [forecast deployment](../docs/forecast-deployment.md). A disabled
or unconfigured outlook is a failed acceptance check, not a silent nightly pass.

Each deploy captures the revision receiving 100% traffic before deployment. It
builds and pushes `backend:<exact Git SHA>`, completes and verifies a Cloud SQL backup,
runs `alembic upgrade head` and initializes the worker vendor schema as a Cloud Run Job, creates a no-traffic revision,
and checks the revision URL until `/health/ready` reports the same SHA with both
database and worker healthy. It then runs live/openapi, Secret Manager reference,
and private Storage upload/download smoke tests before assigning 100% traffic.
The revision name and test URL come from the same uniquely matching commit-tag
entry. Only that tested revision can receive traffic; a different revision
becoming latest during the rollout cannot change the promotion target. Missing
or ambiguous candidate metadata fails before promotion.

Any readiness or smoke failure triggers a fail-closed rollback to the captured
revision. A failed first deployment has no prior revision, so the newly created
service is deleted. Migration failure never changes service traffic.

Live Google Cloud project, billing, budget, DNS, secret values, and real-device
acceptance remain operator-only evidence. The repository contract tests prove the
workflow ordering, no-key/WIF security boundary, freeze behavior, secret
references, private bucket Terraform settings, and rollback paths.

## Turning it off (cost kill switch)

This deployment is intended to run for a demo window, not continuously. Left
running it costs roughly **$56/month in `africa-south1`**, of which about **$45 is
the Cloud Run service alone** — `--min=1` with `--no-cpu-throttling` bills the
container's entire lifetime, not just request time. Cloud SQL `db-f1-micro` is
about $10. Know the shutdown path _before_ you need it.

Read the steps in order. Each one is reversible until the last.

### 1. Stop new deploys (instant, free)

Set the repository variable `DEPLOY_FREEZE=on`. Do this **first**: `gcp-rollout.sh`
hard-codes `--min=1`, so any merge to `main` undoes step 2.

### 2. Scale Cloud Run to zero (~30 seconds, saves ~$45/month, reversible)

```bash
gcloud run services update SERVICE --region=africa-south1 --min=0
```

This is the single largest saving and it keeps the service, database, images and
secrets intact. Expect `/health/ready` to report `worker: "down"` once the
Procrastinate heartbeat ages past 30 seconds, so the nightly smoke will fail while
scaled to zero — that is the intended trade, not a regression. Disable the nightly
workflow or expect red runs.

### 3. Full teardown with Terraform

`terraform destroy` **will fail as-is**, for two separate reasons. Both are
deliberate safety settings, and both must be cleared by hand:

- `google_sql_database_instance.postgres` sets `deletion_protection = true`.
- `google_storage_bucket.media` sets `force_destroy = false`, so destroy fails
  while the bucket holds any object — including noncurrent versions, which
  versioning keeps for 30 days after deletion.

So the sequence is:

```bash
# 1. flip deletion_protection to false and force_destroy to true in gcp-staging.tf
terraform -chdir=infra apply -var=project_id=YOUR_PROJECT_ID   # applies only the flags
terraform -chdir=infra destroy -var=project_id=YOUR_PROJECT_ID
```

Deleting the Cloud SQL instance also deletes its automated _and_ on-demand
backups. Note that `gcp-backup.sh` creates an on-demand backup on every push to
`main`, and on-demand backups are not covered by `retained_backups = 7` — they
accumulate until the instance is deleted.

### 4. Nuclear option — delete the project

If Terraform state has been lost, or you simply want a guarantee rather than a
belief, delete the whole project. Billing stops immediately and there is a 30-day
recovery window:

```bash
gcloud projects delete YOUR_PROJECT_ID
```

This is the only teardown that does not depend on Terraform state being intact,
which is why it is worth knowing.

### Do not "just stop" the Cloud SQL instance

Stopping the instance looks like the obvious saving and is very nearly pointless.
A stopped instance still bills storage, and it bills **$0.01/hour for the idle
IPv4 address** — $7.30/month, against $7.65/month to leave `db-f1-micro` running.
Stopping saves about 35 cents unless you also remove the public IP. Scale Cloud
Run to zero instead (step 2); that is where the money is.

### Verifying it is actually off

Check spend rather than assuming:

```bash
gcloud billing accounts list
gcloud run services list --region=africa-south1
gcloud sql instances list
```

A budget alert is the backstop, not the control. Set one before the first
`terraform apply`, not after.
