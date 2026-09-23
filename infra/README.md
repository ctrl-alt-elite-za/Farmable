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

## One-time operator setup

1. Create a Google Cloud project, attach billing, and configure a budget alert.
2. Enable Terraform and authenticate locally. From the repository root:

   ```bash
   terraform -chdir=infra init
   terraform -chdir=infra apply -var=project_id=YOUR_PROJECT_ID
   ```

   Terraform creates the region-scoped Artifact Registry, private media bucket,
   Cloud SQL/PostGIS-capable instance, runtime/deployer service accounts, and
   GitHub OIDC pool/provider. It creates Secret Manager _containers_ only; it
   never receives or stores provider values in this repository.

   Set the Cloud SQL application user's password out of band and enable the
   supported extension once on the `farmable` database (`CREATE EXTENSION
postgis;`). The current migrations do not execute handwritten SQL, so this
   one-time operator action is intentionally outside Alembic.

3. Add secret versions out of band. Secret names are Terraform outputs or the
   `${name_prefix}-...` resources: `database-url`, `gemini-api-key`,
   `twilio-auth-token`, `turnstile-secret`, `azure-speech-key`,
   `crop-health-api-key`, and `maps-server-api-key`. The database URL must use
   `postgresql+psycopg`, credentials, and the Cloud SQL Unix socket host used by
   Cloud Run's connector, for example `?host=/cloudsql/PROJECT:africa-south1:INSTANCE`.
   Never put a secret value in a GitHub variable or workflow argument.
4. Create these protected `staging` environment variables (names only; values
   are non-secret resource identifiers):

   `GCP_PROJECT_ID`, `GCP_WORKLOAD_IDENTITY_PROVIDER`,
   `GCP_DEPLOYER_SERVICE_ACCOUNT`, `GCP_RUNTIME_SERVICE_ACCOUNT`,
   `GCP_ARTIFACT_REPOSITORY`, `GCP_CLOUD_SQL_INSTANCE`,
   `GCP_CLOUD_SQL_CONNECTION`, `GCP_MEDIA_BUCKET`, `GCP_DATABASE_SECRET`,
   and `GCP_GEMINI_SECRET`.

   `GCP_WORKLOAD_IDENTITY_PROVIDER` is the Terraform output
   `workload_identity_provider`; the Artifact Registry value is
   `REGION-docker.pkg.dev/PROJECT/REPOSITORY`. Use full Secret Manager resource
   IDs for the two secret variables if the project uses a prefix.

5. Set `DEPLOY_FREEZE=on` as a repository variable before an event day.
   The deploy job is skipped before authentication, image push, backup,
   migration, or traffic changes. Remove it after the event.

   It must be repository-scoped, not environment-scoped: both jobs gate on it
   from a job-level `if:`, which GitHub evaluates before a job's environment is
   resolved, and the `frozen` job declares no environment at all. An
   environment variable would be invisible to both and the freeze would
   silently fail open.

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
