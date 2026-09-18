# AWS staging deployment

This directory contains the staging deployment for issue #6. It deliberately
uses one x86_64 EC2 instance in `af-south-1` rather than RDS or ECS: the
repository's API, worker, and PostGIS database already run together in
`compose.yaml`, which keeps the hackathon environment quick to operate.

## What is automated

`aws-staging.yaml` creates the ECR repositories, encrypted private S3 buckets,
SSM parameters, instance role, OIDC deploy role, security group, and EC2
instance. `user-data.sh` installs Docker and Caddy and starts the stack. The
instance has no SSH ingress; operators use SSM.

The workflows in `.github/workflows/` build SHA-tagged images, back up the
database before migrations, deploy through SSM, verify `/health/ready`, and
roll back the image and database backup when a deployment fails. The nightly
workflow runs the staging E2E, degradation, restore, expiry, and assistant
evaluation jobs when those suites are available.

## One-time operator steps

These cannot safely be automated from a repository: enable MFA on the root
user, add billing/credits, choose a domain, confirm the GitHub organization
OIDC trust, and configure budget-alert email recipients. Create the stack with:

```bash
aws cloudformation deploy \
  --region af-south-1 \
  --stack-name farmable-staging \
  --template-file infra/aws-staging.yaml \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides \
    GitHubRepository=ctrl-alt-elite-za/Farmable \
    DomainName=staging.example.com \
    AlertEmail=you@example.com
```

Set the resulting SSM parameters before the first deploy:

```bash
aws ssm put-parameter --region af-south-1 --name /farmable/staging/database-url \
  --type SecureString --value 'postgresql+psycopg://...' --overwrite
aws ssm put-parameter --region af-south-1 --name /farmable/staging/postgres-password \
  --type SecureString --value 'a-new-random-password' --overwrite
aws ssm put-parameter --region af-south-1 --name /farmable/staging/caddy-domain \
  --type String --value staging.example.com --overwrite
```

Configure the `AWS_DEPLOY_ROLE_ARN` GitHub variable with the stack output
`DeployRoleArn`, then enable the `deploy-staging` environment. Never put the
database URL in GitHub variables, workflow YAML, or an image.

The domain must resolve to the instance's Elastic IP before Caddy can obtain a
certificate. Until DNS is configured, use the instance public IP for smoke
testing only; iOS will require HTTPS for the real demo.

## Security and limits

The instance role can read only `/farmable/staging/*` and access only the
three named buckets. The GitHub OIDC role can push to ECR, send commands only
to the tagged instance, and write only to the backup bucket. S3 public access
is blocked and bucket encryption/versioning are enabled. This is a staging
demo environment, not a production design; the database is on the encrypted
instance volume and backups are retained for 14 days.
