# Pull-request checks

Issue #5 adds parallel, path-aware checks without deploying anything. Root
manifests, shared packages, tooling, workflows and migrations invalidate all
consumers. Backend/ML changes also type-check the mobile API consumer. Docs-only
changes skip expensive jobs; the workflow still starts so required checks do
not remain pending.

Reproduce checks with `make lint typecheck test check-no-raw-sql client-check`,
`make security-audit`, `make migration-safety CI_BASE=origin/main`,
`make deployability`, `make e2e-api`, and `make e2e-degradation`.
Docker commands create random credentials, a unique project and a disposable
volume. Cleanup never targets the developer stack. Production images omit
development dependencies; the separate testing target contains pytest.

The existing required `integration-tests` job explicitly runs the full PostgreSQL
photo-sync suite (`apps/backend/tests/integration/test_photo_sync_postgres.py`)
before dependency-failure phases. It is not part of `make test`'s SQLite/unit run
and must not be hidden behind the general integration harness's name filter.

## Automatic changes and explanations

autofix.ci applies Ruff, Prettier, ESLint and client generation. The installed
autofix.ci GitHub App commits changes (including for forks); no writable repo
token is supplied to PR code. Non-mechanical lint failures remain failures.

The `workflow_run` reporter checks out **only the trusted default branch**.
Artifacts are size-bounded JSON data, never extracted or executed. Only fixed
diagnostic codes and positive issue numbers are accepted. No raw error text,
environment dump, command from an artifact, secret value, or PR-provided ref
is rendered. The reporter resolves the PR and head repository from GitHub API
metadata, updates one marked bot comment, and writes the same summary to its
job summary. Raw compiler diagnostics remain in the read-only job logs.

Workflows default to read-only access. CodeQL only receives the separate
code-scanning upload permission. The comment job receives PR-comment access.
The old blanket Dependabot patch auto-merge is now read-only guidance: patch
metadata alone did not prove an update was a security fix, and merge writes
violated #5's privilege separation.

Every job has a 30-minute limit; command checks stop at 25 minutes to leave
time for safe result upload. Tests are never retried. Mark a known flaky test
`@pytest.mark.quarantine(issue=123)`; missing/invalid links fail collection.
Skipped quarantine reasons are reported and generate a warning comment.

## Migrations and audits

Alembic offline mode emits SQL from upgrade operations without a database
connection or API credentials. Squawk 2.65.0 checks only revisions after the
base branch's migration head, not previously approved history. Existing
revision edits/deletions fail. Dangerous new operations require a maintainer
to add `migration-approved`; scanner failures cannot be label-bypassed.
Deployability is independent: a destructive but runnable upgrade can deploy
successfully while migration safety still blocks its merge.
The post-merge main push carries approval only from its exact merged PR and
base commit range; an unrelated approved PR cannot authorize its migration.

pip-audit scans exported, pinned Python dependencies; pnpm audit scans the
workspace lockfile. CVSS/OSV severity gates high/critical findings. Unknown
severity, skipped dependencies, unavailable advisory services and malformed
scanner output fail closed. Reports say whether open Dependabot PRs exist;
they do not claim an unrelated PR fixes a particular advisory.

## Dependencies and activation

This change cannot honestly close #5 yet:

- **#4 remains open for physical-device acceptance:** main now contains the
  Expo app and Maestro launch flows. The `e2e-mobile` job builds a standalone
  release test APK (no Metro server required), enables HTTP only in test-mode
  builds, and verifies Online against its isolated API at `10.0.2.2:8000`.
  It then stops only its own API to verify Offline. Emulator boot may retry
  once only if tests never started; tests themselves are never retried.
  Emulator tests do not prove native camera, LiDAR, microphone, or AR behavior
  on real phones.
- **#7's service fault flags** are tested at the adapter/application boundary
  using isolated fakes. CI Compose stacks explicitly use `ci`/`fake`; real paid
  providers are forbidden in CI. Database/worker stops still exercise real
  dependency failure/recovery. Feature-level provider degradation E2E proof is
  due when feature consumers land; adapter tests do not claim that UI coverage.
- **#23** supplies `make eval-assistant SET=dev`. Both the issue's legacy
  `backend/app/assistant/**` path and the real package's assistant directory
  trigger the required job. No paid API secrets are exposed to fork PR code;
  real paid evaluations need a separately trusted evaluation mechanism in #23.
- The privileged reporter only activates after its workflow/script land on
  the default branch. Unit tests cover safe failure reports before that merge.

After #4 and these workflows land, verify deliberately broken test branches:
type error → `typecheck` comment with `make typecheck`; unformatted TS and stale
client → autofix commit and a green successor run; ORM drop-column upgrade →
deployability passes and safety fails with `DROP COLUMN`/approval guidance;
known critical package → audit fails. Do not merge those broken branches.

`.github/required-checks.json` lists stable check names. Run
`python scripts/required_checks.py` for a non-mutating plan. An administrator
can run `--apply` with `GH_TOKEN` after #4 is verified and main reports all
checks. It preserves other protection rules and existing checks, binds new
checks to their reporting app, and refuses to activate missing checks or to
silently create/overwrite the entire branch-protection object. No branch
rules are changed while this foundation is still awaiting dependencies.
Both `codeql` (workflow execution) and `CodeQL` (Advanced Security findings)
are required; a scanner executing successfully does not override its findings.

## Required checks and local reproduction

`.github/required-checks.json` is the exact list branch protection enforces.
Each check below blocks the pull request when it fails, and its job summary
prints the same local command:

- `lint` — `make lint`
- `typecheck` — `make typecheck`
- `unit-tests` — `make test`
- `integration-tests` — `make test-integration`
- `client-up-to-date` — `make client-check`
- `security-audit` — `make security-audit`
- `gitleaks` — `gitleaks git --redact`
- `codeql` — `See the CodeQL job's analysis`
- `CodeQL` — `See the CodeQL job's analysis`
- `deployability` — `make deployability`
- `migration-safety` — `make migration-safety CI_BASE=<base-sha>`
- `no-raw-sql` — `make check-no-raw-sql`
- `e2e-api` — `make e2e-api`
- `e2e-mobile` — `make e2e-mobile APK=<test-apk>`
- `e2e-degradation` — `make e2e-degradation`
- `assistant-evals` — `make eval-assistant SET=dev`
- `mobile-test` — `make mobile-checks`
- `demo-regression` — `make demo-regression`
- `cloud-review-policy` — `PR_NUMBER=<pr> GITHUB_TOKEN=$(gh auth token) GITHUB_REPOSITORY=ctrl-alt-elite-za/Farmable python3 .github/cloud_review_policy.py`
  — a cloud change needs a specific approver, which CODEOWNERS cannot express:
  Bandile for anyone else's, Tshego for Bandile's

### Flutter

The `mobile-test` job runs entirely through `make mobile-checks` (invoked by
`ci_run.py`, same as every other required check), so this is the exact
command that reproduces every failure the job can report, in order, from the
repository root:

- `node --test scripts/tests/mobile-api.test.mjs` — physical-device API
  configuration policy.
- `bash scripts/check-test-mode.sh` — test mode and demo mode must not both
  be set.
- `flutter pub get --enforce-lockfile` (from `apps/mobile`).
- `dart run tool/generate_tokens.dart --verify` (from `apps/mobile`) — the
  Dart theme must match `design/tokens.css`.
- `dart format --output=none --set-exit-if-changed .` (from `apps/mobile`).
- `flutter analyze` (from `apps/mobile`).
- `flutter test --exclude-tags demo-api` (from `apps/mobile`).
- `flutter test --plain-name 'renders the farm with no network and no spinner' test/home_screen_test.dart`
  (from `apps/mobile`) — the offline-launch smoke: it renders Home from
  local storage with no backend reachable.
- `uv run python scripts/test_mobile_contract.py` — exercises the Flutter
  client against the demo API.

`mobile.yml` carries no pull-request path filter. A workflow that never starts
cannot report a required check, and an unreported required check stays pending
and blocks every unrelated pull request. The `mobile-test` job gates itself on
`scripts/ci_scopes.py` instead, so an unaffected pull request reports
`skipped`, which branch protection accepts as success. If the `scopes` job
itself fails, `mobile-test` runs anyway rather than being skipped — a skipped
required check is reported as success, so failing open on a broken scopes job
would let mobile changes bypass the gate.

The emulator-level proof stays in `e2e-mobile`: `scripts/ci-stack.sh` runs
`e2e/mobile/online_launch.yaml`, then `signup.yaml` and `login.yaml` against
the stack's real API (its fake OTP provider accepts `111111` for the phone and
`222222` for email). It then runs `scan_pan.yaml` from Home through the existing
section scan action in the same test-mode APK, with a fresh device-readiness
check. This verifies labelled synthetic replay, not live crop inference. It
stops the API container, then runs
`e2e/mobile/offline_launch.yaml` against the stopped backend.

### Demo regression

`make demo-regression` replays the existing demo journey on every backend pull
request — local section load, planning preview, replan with a minimum crop
constraint, and plan approval — through
`uv run python -m farmable_backend.demo_api.rehearse`, then runs the existing
planner and demo-API suites. It fixes no product behaviour: a defect it exposes
belongs to the owning frontend or backend issue, or to a narrowly scoped
follow-up.
