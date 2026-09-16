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

- An exclusion reported in one place almost always exists in others. "X is
  missing from Y" means grepping for every list that should name X and fixing
  each one — the reviewer found the instance that happened to bite them, not the
  whole set.
- Switching on a check that was silently skipped will surface failures that have
  nothing to do with the review. They were always there, masked. Fix them in the
  same round; leaving them means the check you just enabled is red for everyone.

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

### Attack your own fix before the reviewer does

Re-reading the diff is not enough — it shows you what you meant, not what you
wrote. Run your fix against inputs you have not already made pass:

- **Enumerate the variants** of whatever you just matched on. A rule keyed on a
  name should be tried qualified, aliased, nested, and reached through an
  attribute chain. A rule keyed on a value should be tried with the value
  rebound, shadowed, or built at runtime.
- **Write the inputs that must _not_ trigger**, not only the ones that must. A
  guardrail that blocks correct code fails just as loudly as one that misses
  bad code, and costs a contributor more.
- **Probe the seams you introduced.** Any suppression, deduplication or caching
  you added to make output tidy can hide a real result — feed it two genuine
  violations in the place it collapses and check both survive.
- **Check portability claims the repo makes.** If the README promises macOS or
  WSL, shell you touched has to work on the oldest interpreter that implies, not
  just the one in front of you.

Findings from this pass are the same as findings from a reviewer: fix them now.
A defect you find yourself is cheap; the same defect found in round three costs
a review cycle and makes every other claim you made look softer.

## 4. Commit and push

- One commit for the review round, unless the findings are genuinely unrelated.
- Message: subject line naming the round, then one bullet per finding — what was
  wrong and what changed. The reviewer should be able to map bullets to findings.
- Push to the PR's own head branch so the review updates in place. Never open a
  second PR for review fixes.
- Check the repo's authorship conventions before committing; confirm `user.name`
  and `user.email` are what this repo expects rather than assuming the default.
- Never force-push a branch you don't own. If history needs rewriting, ask.

### Authorship and tool references

This repository's contributions carry the contributor's identity, not a tool's.
Before committing, and again before pushing:

- Set `user.name` and `user.email` to the repo's contributor, matching how
  existing commits are authored (`git log -5 --format='%an <%ae>'`). Both author
  and committer.
- Strip assistant attribution trailers from the commit message — no
  `Co-Authored-By:` naming a tool or its vendor, no session links.
- Leave no tool or vendor names in the contribution itself: source comments,
  docs, config, test fixtures, PR titles and bodies. Sweep before pushing:

  ```bash
  grep -rIn -i -e 'claude' -e 'anthropic' -e 'co-authored-by' \
    --exclude-dir=.git --exclude-dir=node_modules --exclude-dir=.venv .
  git log -1 --format='%an <%ae>%n%cn <%ce>%n%B' | grep -i -e claude -e anthropic
  ```

  Both should come back empty. Run the sweep before the commit, not after the
  push — amending a pushed commit means a force-push, which step 4 rules out on
  a shared branch.

- If a commit already went out with the wrong authorship, amending and
  force-pushing is a history rewrite: ask the repo owner first.

Commentary is handled in step 5, not here: the default is that the agent does
not post it at all, so there is no agent-authored comment to scrub.

## 5. Reply in this structure

**Draft the reply; let the repo owner post it.** Write the comment out in the
session and hand it over. Do not post it to the PR yourself unless the owner
asks you to in so many words.

This is the default for two reasons. A comment posted by an agent carries a
disclosure footer saying so — that footer is not optional and is never stripped,
because a reviewer acting on the text is entitled to know what wrote it. And the
reply is the author speaking to their reviewer; it reads better, and belongs in
the thread, under their name. Handing over the text gets a clean comment with no
tool branding _and_ honest attribution, because the person who posts it is the
person who signs it.

So: no agent-posted comment, no footer to remove. If the owner does ask you to
post it directly, the footer goes on and stays on — at that point it is an
agent-authored comment and is labelled as one. Never post it stripped, and never
post under the owner's name as though they wrote it.

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

If a later round disproves something you told the reviewer, correct it in the
next reply, in as many words. Descriptions of behaviour are what a reviewer
verifies against; one that quietly stopped being true sends them to check a
thing that no longer matches the code, and they will find the gap before you
admit it. "I said X; it was only true for the bare form, here is what changed"
costs a sentence and keeps the rest of the reply worth reading.

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
- A check that can block a commit or a push needs a documented way to waive a
  single case, and the failure output should name it. Without one, the first
  false positive leaves a contributor editing the checker to get their work in —
  and the next person copies that instead of the waiver.
- "Flake" is not a root cause. Re-run once to confirm; a second failure is real.
- Small, local asks (nits, renames, an added test) → fix and push. Large or
  architectural asks on a PR you don't own → propose in a reply; the author
  decides.
- If a fix is blocked by a permission you don't have, do everything else, then
  state plainly what you were trying to do and what you need. Don't work around
  it.
