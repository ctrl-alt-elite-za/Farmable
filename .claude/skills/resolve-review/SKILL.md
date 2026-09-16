---
name: resolve-review
description: Work a reviewer's findings on a pull request (or an issue listing defects) through to a pushed, validated fix and a structured reply. Use when a review requests changes, a reviewer lists numbered problems, CI is red on a PR you own, or the user says "fix the review comments", "address the feedback", or "resolve issue #N". Covers triage, root-cause fixes, proving each fix, and the reply format.
---

# Resolve a review

A review is a list of claims. Each one is confirmed or refuted against the code,
fixed at the root, proven by something that fails before and passes after, and
answered. Nothing is taken on faith and nothing is left silent.

## 1. Confirm every finding before fixing any of them

Read the actual files first. Reviewers are usually right, but "usually" is not
"always", and a fix aimed at a misread finding is worse than no fix.

For each finding, write down one of:

- **Confirmed** — reproduced it in the tree. Note the exact file and line.
- **Confirmed, broader than reported** — the report is one instance of a general
  problem. Fix the general problem.
- **Refuted** — it does not reproduce. Say so in the reply, with the evidence.

Reproduce it concretely where you can. A grep that misses multiline calls is
proven by writing the multiline call and watching the check pass when it should
fail. That reproduction becomes the regression test in step 3.

Do not start editing until the whole list is triaged. Findings overlap, and
fixing them in report order tends to produce three patches where one would do.

## 2. Fix the cause, not the instance

The reported symptom is a sample, not the specification.

- A check that misses a formatting variant needs a mechanism that formatting
  can't defeat, not one more pattern. Parse the structure; don't widen the regex.
- An ignore rule that misses a filename needs the general form, not two more
  entries.
- A version pinned in two places needs one source of truth, not the two edited
  to agree — they will drift again.

Weigh the alternatives explicitly and pick the one that closes the class of bug.
Record _why_ in the reply — reviewers approve reasoning, not just diffs.

Keep scope tight. Fix what was reported and what is genuinely the same defect.
Do not refactor adjacent code, and do not widen the PR on your own initiative. If
you find something real but out of scope, say so in the reply and leave it.

## 3. Prove each fix

Every fix needs evidence that would have caught the original bug:

- **Guardrail / tooling fix** → a test asserting the reported failure case is now
  caught, plus a negative case that must _not_ trigger. Wire it into the repo's
  test target so it can't rot.
- **Config or ignore rule** → a command whose output shows the new behaviour
  (`git check-ignore -v`, `--version`, a `--check` run).
- **Script behaviour** → exercise each exit path, not just the happy one.

Run the repo's own checks before pushing — lint, typecheck, tests, the full
pre-commit run. Reproduce the original failure first, then show it passing. A
push that turns CI red costs a cycle and the reviewer's trust.

Re-read the diff adversarially before committing: what would make CI reject this?

## 4. Commit and push

- One commit for the review round, unless the findings are genuinely unrelated.
- Message: subject line naming the round, then one bullet per finding — what was
  wrong and what changed. The reviewer should be able to map bullets to findings.
- Push to the PR's own head branch so the review updates in place. Never open a
  second PR for review fixes.
- Check the repo's authorship conventions before committing; confirm `user.name`
  and `user.email` are what this repo expects rather than assuming the default.
- Never force-push a branch you don't own. If history needs rewriting, ask.

## 5. Reply in this structure

One comment per round, on the PR. Not a narration of each fix as you go.

```
## What
One or two sentences a non-engineer can follow. What is now true that wasn't.

## Why
Why this work happened and what it unblocks.

## What's in here
One bullet per finding: what changed, and why that approach over the
alternatives. Name the rejected option and the reason.

## How to verify
Copy-pasteable commands with expected output, per finding. Start with the
reviewer's own reproduction case.
```

Close with what you validated and — explicitly — what you did **not**. If a
check couldn't run (needs network, credentials, a real deploy), say so rather
than implying full coverage. A reviewer who finds an unstated gap stops trusting
the rest of the reply.

## 6. Confirm it actually landed

After pushing, check CI on the new head — not the PR in general, the head SHA
your commit produced. Confirm the checks ran against your commit and aren't
stale results from the previous one.

Read the result for signal beyond pass/fail. An autofix job that passes _without
pushing a follow-up commit_ proves local hooks and CI now agree; that's stronger
evidence than the green tick alone, and worth stating.

If `mergeable_state` is blocked with all checks green, it's waiting on human
approval — say that plainly and stop. Don't push to try to clear it; a push can
dismiss approvals but can't add one.

## Guardrails

- Red CI or a merge conflict on a PR you own is work now, not "waiting on
  review". Never end a round having done nothing about it.
- Never skip, disable, or quarantine a test to get green.
- "Flake" is not a root cause. Re-run once to confirm; a second failure is real.
- Small, local asks (nits, renames, an added test) → fix and push. Large or
  architectural asks on a PR you don't own → propose in a reply; the author
  decides.
- If a fix is blocked by a permission you don't have, do everything else, then
  state plainly what you were trying to do and what you need. Don't work around
  it.
