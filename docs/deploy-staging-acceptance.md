# Demo backend deployment: operator acceptance

Issue #6 is implemented in this repository. What is left is operational: the
Google Cloud project, its billing guardrails, its secret values, and the live
evidence that a push to `main` really deployed, really rolled back, and really
stopped under a freeze. This page is the checklist for that evidence.

Everything below targets one region, `africa-south1` (Johannesburg). The
repository holds no service-account key: GitHub Actions authenticates with
Workload Identity Federation, so there is no credential to rotate or leak.

## 1. One-time setup, before any of the evidence below

Complete `infra/README.md` "One-time operator setup" first, then confirm each
item here.

| Item | Where | Done when |
| --- | --- | --- |
| Project and billing account | Google Cloud console | `gcloud billing projects describe PROJECT_ID` reports `billingEnabled: true` |
| Budget alert | Cloud Billing, Budgets and alerts | A budget scoped to this project, with email alerts at 50%, 90% and 100% of actual spend. Google Cloud never caps spend, so the alert is the only warning before the demo project overruns. |
| Terraform applied | `terraform -chdir=infra apply` | `terraform -chdir=infra output` prints the six outputs |
| PostGIS | the `farmable` database | `CREATE EXTENSION postgis;` has been run once, out of band, as the application user. Alembic never runs it: hand-written SQL in migrations is forbidden (AGENTS.md). |
| Secret values | Secret Manager | Every container Terraform created has an enabled version |
| Protected variables | GitHub, Settings, Environments, staging | The ten names listed in `infra/README.md` step 4 |
| `DEPLOY_FREEZE` | GitHub, Settings, Variables, repository scope | Absent, or not `on`, for a normal day |

Then run the read-only setup check:

```bash
GCP_PROJECT=YOUR_PROJECT_ID GCS_BUCKET=YOUR_PROJECT_ID-farmable-staging-media \
  bash infra/gcp-verify-setup.sh
```

It prints `PASS:` or `FAIL:` per check, reports all of them rather than stopping
at the first, creates nothing, and never reads a secret payload.

The GitHub side is checked by `infra/gcp-required-config.sh`, the deploy
workflow's first step: it names any protected variable that is still unset and
stops before authenticating, so a missing variable never costs an image build.

## 2. Evidence to capture

Capture a link to each workflow run and the named command output, then paste
them into issue #6 as a comment. That comment is what closes the issue.

### 2.1 A push to `main` deploys that exact commit

1. Merge any change to `main` and note the commit SHA.
2. Open the "Deploy demo backend" run for that SHA.
3. Its final step logs `Cloud Run deployed <sha> in africa-south1`.
4. `curl -s https://<service-url>/health/ready` returns `"sha": "<sha>"` with
   `"database": "ok"` and `"worker": "ok"`.

Evidence: run URL, the final log line, the `/health/ready` body.

### 2.2 The deployment freeze blocks a deploy

1. Set the repository variable `DEPLOY_FREEZE` to `on`.
2. Push any commit to `main`.
3. The run shows only the `Deployment freeze is active` job. There is no
   authentication, no image push, no migration and no traffic change.
4. `/health/ready` still reports the previous SHA.
5. Remove `DEPLOY_FREEZE`.

Evidence: run URL showing the skipped `deploy` job, and the unchanged SHA.

### 2.3 A failed check rolls back

Do this deliberately, with a throwaway commit that makes `/health/ready` report
an unhealthy dependency.

1. Before the push, record the serving revision:
   `gcloud run revisions list --service=farmable-backend --region=africa-south1`
2. Push the failing commit.
3. The run ends red at the readiness or smoke step.
4. Its log contains `Deployment failed; restoring previous Cloud Run traffic`.
5. `gcloud run services describe farmable-backend --region=africa-south1 --format='value(status.traffic)'`
   shows 100 percent on the revision from step 1.
6. `/health/ready` reports the previous SHA.

Evidence: the revision list before and after, the rollback log line, the SHA.

### 2.4 A backup existed before the migration ran

1. `gcloud sql backups list --instance=farmable-staging` shows a backup
   described `farmable-<sha>`, timestamped before the migration job started.
2. The deploy log shows `Cloud SQL backup completed before migration` above the
   `Apply approved Alembic migration` step.
3. `alembic current` against the staging database reports the revision that
   migration applied. Run it through the migration job, or through the Cloud SQL
   Auth Proxy from an operator machine.

Evidence: the backup row, both log lines, and the `alembic current` output.

### 2.5 The nightly check runs green

`.github/workflows/nightly-staging.yml` runs at 00:00 UTC, which is 02:00 SAST.
Trigger it once by hand from the Actions tab so this evidence does not wait a
day.

Evidence: run URL and the `Cloud Run demo smoke passed` log line.

### 2.6 No service-account key exists anywhere

1. `gcloud iam service-accounts keys list --iam-account=farmable-staging-deployer@PROJECT_ID.iam.gserviceaccount.com`
   lists only the Google-managed key, never a user-managed one.
2. The repository's GitHub secrets contain no Google credentials JSON.

Evidence: the key list, and a note that no credential secret exists.

## 3. What a failed rollout leaves behind

Traffic rollback is automatic; the database is not. The order is backup,
migrate, deploy a no-traffic revision, verify, then move traffic. A failure
after the migration succeeded therefore leaves a migrated schema while traffic
returns to the previous revision, whose code predates that schema.

That is deliberate. The backup taken minutes earlier is the restore point, and
restoring it automatically would discard anything the previous revision wrote in
between. An additive migration is safe for the older revision to run against; a
destructive one is not, and needs a person.

If the older revision cannot serve the migrated schema:

1. Stop further traffic changes: set `DEPLOY_FREEZE` to `on`.
2. Restore the backup taken for that SHA:
   `gcloud sql backups restore <backup-id> --restore-instance=farmable-staging`
3. Confirm with `alembic current` and `/health/ready`.
4. Remove `DEPLOY_FREEZE`.

A first-ever deployment has no previous revision to return to. The rollout
deletes the service it created, but only after proving that the service holds
exactly the one revision this run deployed; anything else stops and asks for an
operator instead.
