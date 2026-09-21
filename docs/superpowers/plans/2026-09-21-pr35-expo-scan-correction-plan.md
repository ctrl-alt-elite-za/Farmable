# PR 35 implementation plan

Approved design: `../specs/2026-09-21-pr35-expo-scan-correction-design.md`.
The writing-plans skill is unavailable; this explicit plan is the fallback.

1. Integrate current main without rewriting shared history. Restore the precise
   Expo app/tooling paths replaced by this PR to main's versions. Preserve all
   unrelated backend, model-release, and deployment work and the approved spec.
2. Recover and review the earlier TypeScript scan foundation. Add regression
   tests for validation/class-safe tracking, newest-frame processing and resource
   ownership, and session/frame-bound presentation measurements. Implement the
   small pure modules against those tests.
3. Integrate the scan screen with existing Health/Self-test navigation. Preserve
   permission/device/error handling; stop replay on background/unmount. Keep
   fixtures test-only, use crop identities rather than health diagnoses, and
   expose real camera-to-visible latency as unmeasured. Test accessibility,
   viewport-edge controls, navigation, lifecycle, and privacy boundaries.
4. Run complete mobile tests, CI-policy/script tests, lint/type checks, formatting,
   native configuration/bundle checks, and relevant existing regression checks.
   Review the final diff against main; distinguish fixtures/bundles from device
   evidence. Document all unavailable acceptance checks without weakening them.
5. Commit and push to PR 35 only after checking its remote head has not moved.
   Update the PR title/body with Expo-preserving scope, exact verification, and
   model/adapter/device blockers. Leave PR 35 unmerged and issue 18 open.
