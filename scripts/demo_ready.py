"""Answer "can we demo right now?" with READY or a list of problems (#26).

    API_URL=https://… make demo-ready
    API_URL=https://… DEMO_SIGNUP_PROBE_PHONE=+27… make demo-ready ARGS=--send-code

Checks, each a problem when it fails:
- staging is live and ready (database and worker ok) and serves the event
  build: --sha, or origin/main's head;
- the iPhone in docs/devices.json runs that build, and its free-signing
  sideload has more days left than its warning margin;
- staging can send a sign-up code. Only a real code request proves it, and
  that texts a phone and creates an account on staging, so it runs only with
  --send-code, to DEMO_SIGNUP_PROBE_PHONE: a spare team number, never the demo
  account's (a phone can hold one account). Without it the check reports
  "not checked", never fine;
- no step in docs/demo-script.md is still marked ⚠️ or ❌.

The event build is --sha, or origin/main's head after a fresh fetch; the
output names the SHA and whether the fetch worked.

With --e2e it also runs the public API suite (e2e/api) against staging. The
degradation suite stops services, so it never runs against staging.
"""

from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections.abc import Callable
from datetime import date, timedelta
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]

Fetch = Callable[[str], dict[str, Any]]
# (status, error code or None) for a JSON POST.
Post = Callable[[str, dict[str, Any]], tuple[int, str | None]]


def fetch_json(url: str) -> dict[str, Any]:
    with urllib.request.urlopen(url, timeout=10) as response:  # noqa: S310 - fixed https API
        return json.loads(response.read(1_000_000))


def post_json(url: str, body: dict[str, Any]) -> tuple[int, str | None]:
    request = urllib.request.Request(  # noqa: S310 - fixed https API
        url,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=20) as response:  # noqa: S310
            return response.status, None
    except urllib.error.HTTPError as error:
        try:
            code = json.loads(error.read(100_000)).get("error", {}).get("code")
        except ValueError:
            code = None
        return error.code, code


def check_staging(api_url: str | None, sha: str, fetch: Fetch) -> list[str]:
    if not api_url:
        return ["API_URL is not set: cannot check staging"]
    base = api_url.rstrip("/")
    try:
        live = fetch(base + "/health/live")
        ready = fetch(base + "/health/ready")
    except Exception as error:  # noqa: BLE001 - any failure means not ready
        return [f"staging is unreachable ({type(error).__name__})"]
    problems = []
    if live.get("status") != "ok":
        problems.append("staging /health/live is not ok")
    if ready.get("database") != "ok" or ready.get("worker") != "ok":
        problems.append("staging /health/ready reports the database or worker not ok")
    served = ready.get("sha") or live.get("sha")
    if served != sha:
        problems.append(f"staging serves {str(served)[:7]}, not the event build {sha[:7]}")
    return problems


def check_iphone(devices: dict[str, Any], sha: str, today: date) -> list[str]:
    phone = next((d for d in devices.get("devices", []) if d.get("platform") == "ios"), None)
    if phone is None:
        return ["docs/devices.json lists no iPhone"]
    problems = []
    if phone.get("build_sha") != sha:
        installed = str(phone.get("build_sha") or "nothing")[:7]
        problems.append(f"the iPhone runs {installed}, not the event build {sha[:7]}")
    installed_at = phone.get("installed_at")
    valid, margin = phone.get("signature_valid_days"), phone.get("warn_days_before_expiry")
    if not installed_at or valid is None or margin is None:
        problems.append("docs/devices.json does not say when the iPhone was signed")
        return problems
    expires = date.fromisoformat(installed_at) + timedelta(days=valid)
    left = (expires - today).days
    if left <= margin:
        problems.append(
            f"the iPhone's signature expires {expires.isoformat()} ({left} days): re-sign it"
        )
    return problems


def check_signup_codes(
    api_url: str | None, probe_phone: str | None, send: bool, post: Post, stamp: str
) -> list[str]:
    if not send:
        return [
            "sign-up codes not checked: staging refuses every code request until an "
            "SMS provider is connected (#125 or #129). Prove it with ARGS=--send-code "
            "and DEMO_SIGNUP_PROBE_PHONE, a spare team number"
        ]
    if not api_url:
        return []  # Already reported: staging cannot be reached without API_URL.
    if not probe_phone:
        return ["--send-code needs DEMO_SIGNUP_PROBE_PHONE (a spare team number)"]
    status, code = post(
        api_url.rstrip("/") + "/auth/signup",
        {
            "first_name": "Demo",
            "surname": "Readiness",
            "phone": probe_phone,
            "email": f"demo-ready-{stamp}@example.com",
            "password": f"demo-ready-probe-{stamp}",
        },
    )
    if 200 <= status < 300:
        return []
    if code == "account_exists":
        return [
            "the probe phone already has a staging account, so no code was sent; "
            "use another spare number"
        ]
    return [f"staging cannot send a sign-up code (HTTP {status}, {code or 'no code'})"]


_STEP = re.compile(r"^\|\s*(\d+)\s*\|.*\|\s*(⚠️|❌)", re.MULTILINE)


def check_script(script: str) -> list[str]:
    return [
        f"demo script step {number} is still marked {mark}"
        for number, mark in _STEP.findall(script)
    ]


def run_e2e(api_url: str) -> list[str]:
    result = subprocess.run(  # noqa: S603 - fixed argv
        # uv from PATH, as make itself runs it.
        ["uv", "run", "pytest", "e2e/api", "-m", "integration", "-q", "-p", "no:cacheprovider"],  # noqa: S607
        cwd=ROOT,
        env={**os.environ, "API_URL": api_url},
        check=False,
    )
    return [] if result.returncode == 0 else ["the API E2E suite failed against staging"]


def head_of_main() -> tuple[str, bool]:
    """origin/main's head after fetching it, and whether the fetch worked."""
    fetched = (
        subprocess.run(  # noqa: S603 - fixed argv
            ["git", "fetch", "--quiet", "origin", "main"],  # noqa: S607 - git from PATH
            cwd=ROOT,
            check=False,
        ).returncode
        == 0
    )
    sha = subprocess.run(  # noqa: S603 - fixed argv
        ["git", "rev-parse", "origin/main"],  # noqa: S607 - git from PATH
        cwd=ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()
    return sha, fetched


def problems(
    *,
    api_url: str | None,
    sha: str,
    devices: dict[str, Any],
    script: str,
    today: date,
    probe_phone: str | None = None,
    send_code: bool = False,
    fetch: Fetch = fetch_json,
    post: Post = post_json,
) -> list[str]:
    return [
        *check_staging(api_url, sha, fetch),
        *check_iphone(devices, sha, today),
        *check_signup_codes(api_url, probe_phone, send_code, post, today.strftime("%Y%m%d")),
        *check_script(script),
    ]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument("--sha", help="the event build; default origin/main's head")
    parser.add_argument("--e2e", action="store_true", help="also run e2e/api against staging")
    parser.add_argument(
        "--send-code",
        action="store_true",
        help="request a real sign-up code on staging, to DEMO_SIGNUP_PROBE_PHONE",
    )
    args = parser.parse_args(argv)
    found: list[str] = []
    if args.sha:
        sha = args.sha
        print(f"Event build {sha[:7]} (given with --sha)")
    else:
        sha, fetched = head_of_main()
        if fetched:
            print(f"Event build {sha[:7]} (origin/main, fetched just now)")
        else:
            print(f"Event build {sha[:7]} (origin/main, NOT fetched: may be out of date)")
            found.append("could not fetch origin/main, so the event build may be out of date")
    api_url = os.environ.get("API_URL")
    found += problems(
        api_url=api_url,
        sha=sha,
        devices=json.loads((ROOT / "docs/devices.json").read_text(encoding="utf-8")),
        script=(ROOT / "docs/demo-script.md").read_text(encoding="utf-8"),
        today=date.today(),
        probe_phone=os.environ.get("DEMO_SIGNUP_PROBE_PHONE"),
        send_code=args.send_code,
    )
    if args.e2e and api_url:
        found += run_e2e(api_url)
    if not found:
        print(f"READY: build {sha[:7]}")
        return 0
    print(f"NOT READY for build {sha[:7]}:")
    for problem in found:
        print(f"  - {problem}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
