# Issue 17 implementation plan

> Historical Expo plan, superseded by the Flutter port after PR #47 review.
> See [offline-queue.md](../../offline-queue.md) for the current implementation.

Approved spec: `../specs/2026-09-21-issue17-durable-mobile-queue-design.md`.
The writing-plans skill is unavailable; this is the explicit fallback plan.

1. Add the approved mobile-only SQL exception and SDK-compatible dependencies.
2. Define validated observation/mutation types and the narrow database port.
   Add failing tests with an actual temporary SQLite database, then implement
   schema migrations, atomic saves, scoped reads, idempotent enqueue, recovery,
   claims, acknowledgements, and retry transitions.
3. Implement app-owned photo staging and a local observation service. Test
   failed copy/commit, safe cleanup, local paths, and missing-file behavior.
4. Implement a single-runner queue, persisted bounded backoff, dependency
   ordering, response validation, cancellation, and scope-safe lifecycle.
   Exercise these with real SQLite and an injected fake transport/clock.
5. Add native SQLite/filesystem adapters and foreground/connectivity wiring.
   Production has no transport or invented identity. Supply a test-build-only
   native restart probe with explicit seed/verify phases and no live requests.
6. Run mobile and repository checks, inspect the diff, document limitations,
   and publish an unmerged review PR. Do not close #17 or claim real server
   synchronization/native acceptance without its corresponding evidence.

## Implementation evidence

- Implemented the six steps' local code and a test-mode-only restart probe;
  no farmer-facing screen or real HTTP transport was added.
- Mobile: 115 tests pass across 14 suites. SQLite/file tests use actual
  disposable local storage; lifecycle and transport boundaries are injected.
- Android and iOS test-mode Hermes bundle exports pass. These are bundling
  checks, not native runtime/device acceptance.
- Lint, TypeScript/mypy, raw-SQL guard, generated-client check, dependency
  audit, and migration safety pass. No backend migrations were added.
- Android emulator/iOS device tools are unavailable locally. Follow
  `docs/offline-queue.md` for native restart acceptance; do not mark #17 done.
