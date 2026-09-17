"""Plan/apply ONLY required-status checks. Preserve every other branch-protection setting."""

import argparse
import base64
import json
import os
import urllib.error
from pathlib import Path

from ci_report import all_pages, request_json


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    repo = os.environ.get("GITHUB_REPOSITORY", "ctrl-alt-elite-za/Farmable")
    prefix = "/repos/" + repo
    required = json.loads(Path(".github/required-checks.json").read_text(encoding="utf-8"))
    print("Required checks: " + ", ".join(required))
    if not args.apply:
        print("Plan only. Apply after workflows merge, #4 lands, and main reports all checks.")
        return
    metadata = request_json(prefix)
    if not metadata.get("permissions", {}).get("admin"):
        raise RuntimeError("A repository administrator must configure branch protection")
    if request_json(prefix + "/issues/4")["state"] != "closed":
        raise RuntimeError("Refusing to activate incomplete mobile checks before #4 is verified")
    package = request_json(prefix + "/contents/apps/mobile/package.json?ref=main")
    mobile = json.loads(base64.b64decode(package["content"]))
    if "expo" not in mobile.get("dependencies", {}):
        raise RuntimeError("Main does not contain #4's Expo app")
    flows = request_json(prefix + "/contents/e2e/mobile?ref=main")
    if not any(item["name"].endswith(".yaml") and item["type"] == "file" for item in flows):
        raise RuntimeError("Main does not contain real Maestro flows")
    branch = request_json(prefix + "/branches/main")
    runs = all_pages(prefix + f"/commits/{branch['commit']['sha']}/check-runs", "check_runs")
    latest: dict[str, dict] = {}
    for run in sorted(runs, key=lambda item: item["id"], reverse=True):
        latest.setdefault(run["name"], run)
    if any(
        name not in latest or latest[name]["conclusion"] not in {"success", "skipped", "neutral"}
        for name in required
    ):
        raise RuntimeError("Required jobs must first report successful/skipped checks on main")
    endpoint = prefix + "/branches/main/protection/required_status_checks"
    try:
        current = request_json(endpoint)
    except urllib.error.HTTPError as error:
        if error.code != 404:
            raise
        # Never create/overwrite the whole branch-protection object implicitly.
        raise RuntimeError(
            "Branch protection must exist before status-check configuration"
        ) from error
    checks = {item["context"]: item for item in current.get("checks", [])}
    for context in current.get("contexts", []):
        checks.setdefault(context, {"context": context, "app_id": -1})
    for name in required:
        checks[name] = {"context": name, "app_id": latest[name]["app"]["id"]}
    request_json(endpoint, "PATCH", {"strict": True, "checks": list(checks.values())})
    print("Required checks enabled, with existing branch rules and checks preserved")


if __name__ == "__main__":
    main()
