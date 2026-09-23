import importlib.util
from pathlib import Path

import pytest
import yaml

ROOT = Path(__file__).parents[2]
_spec = importlib.util.spec_from_file_location(
    "cloud_review_policy", ROOT / ".github/cloud_review_policy.py"
)
policy = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(policy)

HEAD = "a" * 40
OLD = "b" * 40
LEAD, REVIEWER, OTHER = "bandilleee", "TshegofatsoMkhabela", "Kea-nhlapo"
CLOUD = ["infra/gcp-rollout.sh"]


def review(login: str, state: str, commit: str = HEAD) -> dict:
    return {"user": {"login": login}, "state": state, "commit_id": commit}


@pytest.mark.parametrize(
    ("author", "approver", "passes"),
    [
        # Anyone but the lead needs the lead -- the co-owner is not enough.
        (OTHER, LEAD, True),
        (OTHER, REVIEWER, False),
        (REVIEWER, LEAD, True),
        # The lead's own cloud change needs the designated reviewer, not anyone.
        (LEAD, REVIEWER, True),
        (LEAD, OTHER, False),
    ],
)
def test_the_required_approver_depends_on_who_opened_the_change(author, approver, passes):
    ok, message = policy.evaluate(author, CLOUD, [review(approver, "APPROVED")], HEAD)
    assert ok is passes
    if not passes:
        assert f"@{policy.required_approver(author)}" in message


def test_non_cloud_changes_need_no_extra_approval():
    ok, _ = policy.evaluate(OTHER, ["apps/mobile/lib/main.dart"], [], HEAD)
    assert ok


def test_an_approval_on_an_earlier_commit_does_not_carry_forward():
    ok, _ = policy.evaluate(OTHER, CLOUD, [review(LEAD, "APPROVED", OLD)], HEAD)
    assert not ok


def test_a_dismissed_approval_does_not_count():
    reviews = [review(LEAD, "APPROVED"), review(LEAD, "DISMISSED")]
    assert not policy.evaluate(OTHER, CLOUD, reviews, HEAD)[0]


def test_changes_requested_withdraws_approval_but_a_comment_does_not():
    withdrawn = [review(LEAD, "APPROVED"), review(LEAD, "CHANGES_REQUESTED")]
    assert not policy.evaluate(OTHER, CLOUD, withdrawn, HEAD)[0]
    commented = [review(LEAD, "APPROVED"), review(LEAD, "COMMENTED")]
    assert policy.evaluate(OTHER, CLOUD, commented, HEAD)[0]


def test_moving_a_file_out_of_the_cloud_counts_as_a_cloud_change():
    paths = policy.changed_paths(
        [{"filename": "misc/rollout.sh", "previous_filename": "infra/gcp-rollout.sh"}]
    )
    assert not policy.evaluate(OTHER, paths, [], HEAD)[0]


def test_the_policy_guards_its_own_files():
    for path in (
        ".github/cloud_review_policy.py",
        ".github/workflows/cloud-review-policy.yml",
        "scripts/tests/test_cloud_review_policy.py",
    ):
        assert policy.is_cloud(path)


def test_every_named_cloud_file_exists():
    """A renamed file would silently fall out of the policy, so a stale entry fails here."""
    missing = [path for path in policy.CLOUD_FILES if not (ROOT / path).exists()]
    assert missing == []


def test_the_rule_is_loaded_from_the_base_branch_not_the_pull_request():
    workflow = yaml.safe_load((ROOT / ".github/workflows/cloud-review-policy.yml").read_text())
    checkout = workflow["jobs"]["cloud-review-policy"]["steps"][0]
    assert checkout["with"]["ref"] == "${{ github.event.pull_request.base.sha }}"
    assert checkout["with"]["persist-credentials"] is False
    triggers = workflow.get("on", workflow.get(True))
    assert set(triggers["pull_request_review"]["types"]) == {"submitted", "dismissed"}
