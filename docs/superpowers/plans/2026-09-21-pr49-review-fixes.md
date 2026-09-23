# PR49 review-fix implementation checklist

Approved design: `../specs/2026-09-21-pr49-review-fixes-design.md`.
Writing-plans skill unavailable; this is the explicit fallback plan.

1. Add recovery, timestamp, public-error, worker-lifecycle and CI-selection regressions.
2. Add explicit attempt-fenced recovery and shared photo policy; preserve schema/history.
3. Bound new observation times, retain accepted replays, and fix smaller review findings.
4. Run real PostgreSQL recovery races and existing migration/ownership tests.
5. Document the amended contract and regenerate the client; run local quality gates.
6. Review, commit, push PR49, and report each review disposition and outstanding gates.

No merge, deployment, live data/storage changes, or branch-protection changes.
