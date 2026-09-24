"""Who must approve a pull request that changes the cloud.

CODEOWNERS gives every file one fixed list of approvers, identical for every pull
request, so it cannot say "Kea's cloud change needs Bandile, not Tshego". This check
supplies the half that depends on who opened the pull request:

- a cloud change opened by the cloud lead needs the lead's designated reviewer;
- a cloud change opened by anyone else needs the lead.

It runs as a required status check. The workflow loads this file from the base
branch, never from the pull request under review, so a pull request cannot rewrite
the rule that judges it -- and editing this file is itself a cloud change.
"""

from __future__ import annotations

import json
import os
import sys
import urllib.request
from collections.abc import Iterable

LEAD = "bandilleee"
LEAD_REVIEWER = "TshegofatsoMkhabela"

CLOUD_PREFIXES = ("infra/",)
CLOUD_FILES = frozenset(
    {
        ".github/CODEOWNERS",
        ".github/cloud_review_policy.py",
        ".github/workflows/cloud-review-policy.yml",
        ".github/workflows/deploy-staging.yml",
        ".github/workflows/nightly-staging.yml",
        "scripts/tests/test_cloud_review_policy.py",
        "scripts/tests/test_staging_infrastructure.py",
        "scripts/tests/test_forecast_deployment.py",
        "docs/deploy-staging-acceptance.md",
        "docs/forecast-deployment.md",
    }
)


def is_cloud(path: str) -> bool:
    return path in CLOUD_FILES or path.startswith(CLOUD_PREFIXES)


def changed_paths(files: Iterable[dict]) -> list[str]:
    """Every path a pull request touches, including where a renamed file came from.

    Moving a file out of infra/ changes the cloud as surely as editing it, so the
    source path of a rename counts too.
    """
    paths = []
    for item in files:
        paths.append(item["filename"])
        if item.get("previous_filename"):
            paths.append(item["previous_filename"])
    return paths


def required_approver(author: str) -> str:
    return LEAD_REVIEWER if author == LEAD else LEAD


def effective_reviews(reviews: Iterable[dict], head_sha: str) -> dict[str, str]:
    """Each reviewer's standing verdict on the current head commit.

    Reviews arrive oldest first. A comment neither grants nor withdraws approval. A
    dismissed review, or one left on an earlier commit, no longer counts -- so the
    rule holds even if stale-review dismissal is ever switched off.
    """
    verdicts: dict[str, str] = {}
    for review in reviews:
        login = (review.get("user") or {}).get("login")
        state = review.get("state")
        if not login or state not in {"APPROVED", "CHANGES_REQUESTED", "DISMISSED"}:
            continue
        if state == "DISMISSED" or review.get("commit_id") != head_sha:
            verdicts.pop(login, None)
        else:
            verdicts[login] = state
    return verdicts


def evaluate(
    author: str, paths: Iterable[str], reviews: Iterable[dict], head_sha: str
) -> tuple[bool, str]:
    cloud = sorted({path for path in paths if is_cloud(path)})
    if not cloud:
        return True, "No cloud files changed; no extra approval required."
    approver = required_approver(author)
    if effective_reviews(reviews, head_sha).get(approver) == "APPROVED":
        return True, f"Cloud change by @{author} is approved by @{approver}."
    return False, (
        f"Cloud change by @{author} needs approval from @{approver} on the latest "
        f"commit. Cloud files touched: {', '.join(cloud)}"
    )


def _get(url: str, token: str):
    request = urllib.request.Request(  # noqa: S310 - fixed https API host
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 - fixed API host
        return json.load(response)


def _all(url: str, token: str) -> list[dict]:
    items: list[dict] = []
    page = 1
    while True:
        batch = _get(f"{url}?per_page=100&page={page}", token)
        items.extend(batch)
        if len(batch) < 100:
            return items
        page += 1


def main() -> int:
    repo = os.environ["GITHUB_REPOSITORY"]
    token = os.environ["GITHUB_TOKEN"]
    base = f"https://api.github.com/repos/{repo}/pulls/{os.environ['PR_NUMBER']}"
    # Read the pull request fresh rather than from the event payload: a review event
    # can carry a head commit that a later push has already replaced.
    pull = _get(base, token)
    ok, message = evaluate(
        pull["user"]["login"],
        changed_paths(_all(base + "/files", token)),
        _all(base + "/reviews", token),
        pull["head"]["sha"],
    )
    print(message)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
