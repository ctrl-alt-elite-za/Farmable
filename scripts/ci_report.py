"""Privileged reporter: trusted base code only, enum-only artifacts, never PR code/logs."""

import io
import json
import os
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

from ci_checks import CHECKS, DIAGNOSTICS

MARKER = "<!-- farmable-ci-report -->"
WORKFLOWS = {"Farmable PR checks", "gitleaks", "autofix.ci", "CodeQL"}


def safe_result(data: dict) -> dict:
    if not isinstance(data, dict):
        raise ValueError("Result must be an object")
    name = data.get("check")
    if name not in CHECKS or type(data.get("failed")) is not bool:
        raise ValueError("Invalid check result")
    codes = data.get("diagnostics", [])
    issues = data.get("quarantined", [])
    if not isinstance(codes, list) or not isinstance(issues, list):
        raise ValueError("Invalid diagnostic data")
    return {
        "check": name,
        "failed": data["failed"],
        "diagnostics": [
            code for code in codes[:20] if isinstance(code, str) and code in DIAGNOSTICS
        ],
        "quarantined": [n for n in issues[:100] if type(n) is int and 0 < n < 1_000_000],
    }


def read_artifact(payload: bytes) -> list[dict]:
    if len(payload) > 1_000_000:
        raise ValueError("Oversized report artifact")
    results = []
    with zipfile.ZipFile(io.BytesIO(payload)) as archive:
        if len(archive.infolist()) > 20:
            raise ValueError("Too many report entries")
        for item in archive.infolist():
            # No extraction, paths, shell evaluation, pickle, or executable artifact data.
            if Path(item.filename).name not in {name + ".json" for name in CHECKS}:
                continue
            if item.file_size > 16_384:
                raise ValueError("Oversized report entry")
            results.append(safe_result(json.loads(archive.read(item))))
    return results


def render(results: list[dict], failed_jobs: list[dict], dependabot_count: int) -> str:
    text = MARKER + "\n## Farmable check report\n\n"
    failures = {r["check"]: r for r in results if r["failed"]}
    for job in failed_jobs:
        name = job["name"]
        # Never render arbitrary job or step names from PR-controlled workflow YAML.
        if name not in CHECKS:
            continue
        failures.setdefault(name, {"diagnostics": [], "quarantined": []})
        if job.get("conclusion") == "timed_out":
            failures[name]["diagnostics"] = ["timeout"]
    if not failures:
        text += "No failed checks reported so far.\n"
    for name in sorted(failures):
        text += f"### {name}\n\nReproduce: `{CHECKS[name][0]}`\n\n{CHECKS[name][1]}\n"
        for code in failures[name]["diagnostics"]:
            text += f"\n- {DIAGNOSTICS[code]}"
        if "timeout" in failures[name]["diagnostics"]:
            job = next((j for j in failed_jobs if j["name"] == name), {})
            step = next(
                (
                    s["name"]
                    for s in job.get("steps", [])
                    if s.get("status") == "in_progress" or s.get("conclusion") == "timed_out"
                ),
                "Run " + name,
            )
            if step not in {
                "Run " + name,
                "Setup tooling",
                "Build test-mode APK",
                "Install pinned Maestro",
                "Retry emulator boot once",
                "Set up job",
            }:
                step = "Unrecognized step; inspect the timed-out job"
            text += f"\n- Stuck step: `{step}` (30-minute job limit)."
        if name == "security-audit":
            text += (
                f"\n- {dependabot_count} open Dependabot PR(s); check for a matching fix."
                if dependabot_count
                else "\n- No open Dependabot fix PR was found."
            )
        text += "\n\n"
    issues = sorted({issue for result in results for issue in result["quarantined"]})
    for issue in issues:
        text += f"Warning: this run contains a quarantined test linked to #{issue}.\n"
    for result in results:
        if "prerequisite" in result["diagnostics"]:
            text += f"Warning: `{result['check']}` is NOT VERIFIED; prerequisite work is pending.\n"
    text += "\nRaw logs and environment values are never included.\n"
    return text


def request_json(path: str, method: str = "GET", data: dict | None = None):
    api = "https://api.github.com"
    token = os.environ["GH_TOKEN"]
    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": "2022-11-28",
    }
    request = urllib.request.Request(  # noqa: S310 -- fixed HTTPS API.
        api + path,
        headers=headers,
        method=method,
        data=json.dumps(data).encode() if data is not None else None,
    )
    if data is not None:
        request.add_header("Content-Type", "application/json")
    with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310 -- fixed HTTPS API.
        return json.load(response)


def all_pages(path: str, key: str | None = None) -> list:
    results = []
    separator = "&" if "?" in path else "?"
    for page in range(1, 101):
        data = request_json(f"{path}{separator}per_page=100&page={page}")
        items = data[key] if key else data
        results.extend(items)
        if len(items) < 100:
            return results
    raise ValueError("API pagination limit reached")


def artifact_bytes(repo: str, artifact_id: int) -> bytes:
    # Resolve the API redirect WITH auth, then download the signed artifact URL WITHOUT auth.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, req, fp, code, msg, headers, newurl):
            return None

    import urllib.error

    url = f"https://api.github.com/repos/{repo}/actions/artifacts/{artifact_id}/zip"
    opener = urllib.request.build_opener(NoRedirect())
    request = urllib.request.Request(  # noqa: S310 -- fixed HTTPS API.
        url, headers={"Authorization": "Bearer " + os.environ["GH_TOKEN"]}
    )
    try:
        opener.open(request, timeout=30)
    except urllib.error.HTTPError as error:
        if error.code != 302:
            raise
        signed_url = error.headers["Location"]
    else:
        raise ValueError("Expected signed artifact redirect")
    parsed = urllib.parse.urlparse(signed_url)
    if parsed.scheme != "https" or parsed.username or parsed.password:
        raise ValueError("Invalid signed artifact URL")
    with urllib.request.urlopen(signed_url, timeout=30) as response:  # noqa: S310 -- validated HTTPS.
        return response.read(1_000_001)


def main() -> None:
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text(encoding="utf-8"))
    source = event["workflow_run"]
    if source["event"] != "pull_request" or source["name"] not in WORKFLOWS:
        return
    repo = os.environ["GITHUB_REPOSITORY"]
    prefix = f"/repos/{repo}"
    # PR number comes from GitHub API metadata, NEVER an artifact.
    prs = all_pages(prefix + "/pulls?state=open")
    prs = [
        pr
        for pr in prs
        if pr["head"]["sha"] == source["head_sha"]
        and pr["head"]["ref"] == source["head_branch"]
        and pr["head"]["repo"]["full_name"] == source["head_repository"]["full_name"]
    ]
    runs = all_pages(
        prefix + "/actions/runs?event=pull_request&head_sha=" + source["head_sha"], "workflow_runs"
    )
    selected: dict[str, dict] = {}
    for run in sorted(runs, key=lambda item: item["id"], reverse=True):
        if run["name"] in WORKFLOWS:
            selected.setdefault(run["name"], run)
    results: list[dict] = []
    failures: list[dict] = []
    for run in selected.values():
        jobs = all_pages(prefix + f"/actions/runs/{run['id']}/jobs", "jobs")
        failures.extend(
            job
            for job in jobs
            if job.get("conclusion") in {"failure", "timed_out", "cancelled", "action_required"}
        )
        artifacts = all_pages(prefix + f"/actions/runs/{run['id']}/artifacts", "artifacts")
        for artifact in artifacts:
            if artifact["name"].startswith("ci-result-") and not artifact["expired"]:
                try:
                    results.extend(read_artifact(artifact_bytes(repo, artifact["id"])))
                except (ValueError, KeyError, zipfile.BadZipFile, json.JSONDecodeError):
                    # Invalid untrusted data never becomes executable/rendered text.
                    continue
    dependabot_count = sum(
        pr["user"]["login"] == "dependabot[bot]" for pr in all_pages(prefix + "/pulls")
    )
    body = render(results, failures, dependabot_count)
    for pr in prs:
        comments = all_pages(prefix + f"/issues/{pr['number']}/comments")
        previous = next(
            (
                c
                for c in comments
                if c["body"].startswith(MARKER) and c["user"]["login"] == "github-actions[bot]"
            ),
            None,
        )
        if previous:
            request_json(prefix + f"/issues/comments/{previous['id']}", "PATCH", {"body": body})
        elif failures or any(r["failed"] or r["quarantined"] for r in results):
            request_json(prefix + f"/issues/{pr['number']}/comments", "POST", {"body": body})
    if os.environ.get("GITHUB_STEP_SUMMARY"):
        with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
            stream.write(body)


if __name__ == "__main__":
    main()
