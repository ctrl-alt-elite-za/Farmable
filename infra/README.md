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

5. Set `DEPLOY_FREEZE=on` on the protected environment before an event day.
   The deploy job is skipped before authentication, image push, backup,
   migration, or traffic changes. Remove it after the event.

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

Any readiness or smoke failure triggers a fail-closed rollback to the captured
revision. A failed first deployment has no prior revision, so the newly created
service is deleted. Migration failure never changes service traffic.

Live Google Cloud project, billing, budget, DNS, secret values, and real-device
acceptance remain operator-only evidence. The repository contract tests prove the
workflow ordering, no-key/WIF security boundary, freeze behavior, secret
references, private bucket Terraform settings, and rollback paths.
