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

- **#4 remains open:** no Expo app/APK or Maestro flows exist on main. The
  `e2e-mobile` job explicitly reports **NOT VERIFIED**, rather than fabricating
  a passing flow. When the app/config/flows land, it builds with test mode,
  installs the APK, runs Maestro against the isolated API, and retries emulator
  boot once only if tests never started. Android API URLs use `10.0.2.2:8000`.
  PR #31 supplies a standalone release test APK (no Metro server required),
  enables HTTP only in test-mode builds, verifies Online against that isolated
  API, then stops only its own API to verify the Offline flow. Emulator tests
  do not prove native camera, LiDAR, microphone, or AR behavior on real phones.
- **#7's service fault flags** join the degradation suite when those services
  exist. Today database/worker stops exercise real dependency failure/recovery;
  there is no claim that unimplemented external-service flags were tested.
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
