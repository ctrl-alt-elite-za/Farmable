# PR 34: promote only the tested Cloud Run revision

## Scope

Repair the mismatch between the commit-tag URL tested by the rollout and the
service-wide latest revision currently promoted. Leave PR 34 unmerged. Do not
change cloud infrastructure, migration ordering, or the first-deployment cleanup
policy.

## Design

After deployment, read one service JSON snapshot. Require exactly one traffic
entry matching `sha-${COMMIT_SHA}`, with a nonempty revision name and an HTTPS
URL. Resolve both candidate values from that entry and promote only that revision
after all existing health and smoke checks pass. Never use
`latestCreatedRevisionName` to select the promotion target.

Keep the existing latest-created lookup solely as the first-deployment cleanup
fallback; it must never select production traffic. The existing cleanup guard
still requires the service to contain exactly that one revision. An unresolved or
ambiguous tag fails before health checks or promotion and follows the existing
rollback path. A previously serving revision is restored on failure.

This is narrower than introducing cross-operator deployment locks or assigning
revision names in advance. It fixes which immutable revision is promoted without
changing deployment naming or retry behaviour. Concurrent external changes to
service configuration remain an operator coordination concern.

## Verification

- A newer, unrelated latest revision must not replace the tagged, tested revision
  as the promotion target.
- Missing tags, duplicate matching tags, missing revision names, and invalid URLs
  must fail without promoting any candidate.
- Failures on an existing service restore the captured previous revision and
  never delete the service.
- Existing successful rollout and guarded first-deployment cleanup tests pass.
- Run all script tests, formatting, lint, and type checks; no real GCP resources
  are modified. Live deployment acceptance remains outstanding.
