# PR 34 production review design

## Goal

Close the deployment safety gaps found during review without expanding the
Google Cloud staging architecture or claiming live-project acceptance.

## Design

- Change the versioned media bucket lifecycle rule so only noncurrent object
  versions are deleted, after 30 days in the noncurrent state. Live media must
  not expire because of age.
- Resolve the nightly smoke target from the Cloud Run service after OIDC
  authentication. Require one revision to receive 100 percent of traffic and
  read the expected commit SHA from that immutable revision.
- Exercise both liveness and readiness in the shared smoke script. Readiness
  must report the expected SHA and healthy database and worker components.
- Remove remote storage-smoke artifacts on both success and failure.
- Cover the contracts with repository tests and update operator documentation.

The workflow remains fail-closed and does not deploy, migrate, or change
traffic during the nightly check.

## Verification

Run the infrastructure contract tests, shell syntax checks, formatting,
linting, type checking, and the repository verification suite. Live Google
Cloud acceptance remains an operator-owned step.
