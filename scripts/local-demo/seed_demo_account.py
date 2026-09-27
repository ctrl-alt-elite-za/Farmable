"""Seed Thandi's demo farm: on the LOCAL fallback backend, or an existing account.

    bash scripts/local-demo/start.sh
    uv run python scripts/local-demo/seed_demo_account.py

    # The real demo account on staging (already signed up and verified):
    uv run python scripts/local-demo/seed_demo_account.py \
        --api https://farmable-backend-mm2c2uwikq-bq.a.run.app --existing EMAIL_OR_PHONE

Creates (or logs into) an invented account and fills its farm through the
public API, the way phones and the web would: four sections (one walked and
mapped), current plantings, tasks (one overdue), health checks (one needing a
look) and money in and out. Every record has a fixed id derived from its name,
so running this twice replays the same mutations instead of duplicating them.

Local mode signs up with the fake provider's fixed codes 111111 (phone) and
222222 (email), so it only runs against localhost. --existing never signs up:
it logs into an account you already own, asking for the password at a prompt
(or reading DEMO_PASSWORD), and only then adds the records.
"""

from __future__ import annotations

import argparse
import getpass
import json
import os
import sys
import urllib.error
import urllib.request
import uuid
from datetime import UTC, date, datetime, time, timedelta
from typing import Any

NAMESPACE = uuid.UUID("7d4f0c9e-2b1a-4c3e-9f5d-6a8b0c1d2e3f")

DEMO_EMAIL = "thandi.demo@example.com"
ACCOUNT = {
    "first_name": "Thandi",
    "surname": "Mokoena",
    # Invented. The local fake provider sends nothing anywhere.
    "phone": "+27825550123",
    "email": DEMO_EMAIL,
    "password": "three blind field mice",
}
FARM_NAME = "Thandi Farm"


def stable_id(*parts: str) -> str:
    return str(uuid.uuid5(NAMESPACE, "/".join(parts)))


def square(lat: float, lon: float, north_m: float, east_m: float) -> dict[str, Any]:
    """A closed GeoJSON polygon of about north_m x east_m metres from a corner."""
    dlat = north_m / 111_320
    dlon = east_m / 97_000  # metres per degree of longitude near 29.7 S
    ring = [(lon, lat), (lon + dlon, lat), (lon + dlon, lat + dlat), (lon, lat + dlat)]
    return {"type": "Polygon", "coordinates": [[[x, y] for x, y in [*ring, ring[0]]]]}


class Api:
    def __init__(self, base: str) -> None:
        self.base = base.rstrip("/")
        self.token: str | None = None

    def call(self, method: str, path: str, body: dict[str, Any] | None = None) -> tuple[int, Any]:
        headers = {"Content-Type": "application/json"}
        if self.token:
            headers["Authorization"] = f"Bearer {self.token}"
        request = urllib.request.Request(  # noqa: S310 - local API only
            self.base + path,
            data=None if body is None else json.dumps(body).encode(),
            headers=headers,
            method=method,
        )
        try:
            with urllib.request.urlopen(request, timeout=30) as response:  # noqa: S310
                raw = response.read()
                return response.status, json.loads(raw) if raw else None
        except urllib.error.HTTPError as error:
            raw = error.read()
            try:
                return error.code, json.loads(raw)
            except ValueError:
                return error.code, raw.decode(errors="replace")

    def ok(self, method: str, path: str, body: dict[str, Any] | None = None) -> Any:
        status, data = self.call(method, path, body)
        if not 200 <= status < 300:
            raise SystemExit(f"{method} {path} failed: HTTP {status} {data}")
        return data


def sign_in(api: Api) -> None:
    status, data = api.call("POST", "/auth/signup", ACCOUNT)
    if 200 <= status < 300:
        user_id = data["user_id"]
        api.ok("POST", "/auth/verify/phone", {"user_id": user_id, "code": "111111"})
        api.ok("POST", "/auth/verify/email", {"user_id": user_id, "code": "222222"})
        print("Created and verified the demo account")
    elif status != 409:
        raise SystemExit(f"Sign-up failed: HTTP {status} {data}")
    else:
        print("Demo account exists; logging in")
    status, session = api.call(
        "POST", "/auth/login", {"identifier": DEMO_EMAIL, "password": ACCOUNT["password"]}
    )
    if status != 200:
        # An account that was created but never verified cannot log in, and its
        # id is not given out again. On this local stack, start clean instead.
        raise SystemExit(
            "Could not log in to the demo account (it may be unverified). "
            "Run: bash scripts/local-demo/reset.sh, then seed again."
        )
    api.token = session["access_token"]


def log_in_existing(api: Api, identifier: str) -> None:
    password = os.environ.get("DEMO_PASSWORD") or getpass.getpass(f"Password for {identifier}: ")
    status, session = api.call(
        "POST", "/auth/login", {"identifier": identifier, "password": password}
    )
    if status != 200:
        code = session.get("error", {}).get("code") if isinstance(session, dict) else session
        raise SystemExit(f"Could not log in as {identifier}: HTTP {status} {code}")
    api.token = session["access_token"]


def seed(api: Api, today: date) -> None:
    farms = api.ok("GET", "/farms")["items"]
    if len(farms) != 1:
        raise SystemExit(f"expected one farm on the account, found {len(farms)}")
    farm = farms[0]["id"]
    api.ok("PATCH", "/account/farm", {"name": FARM_NAME})
    base = f"/farms/{farm}"

    def post(resource: str, key: str, body: dict[str, Any]) -> None:
        body = {"mutation_id": stable_id("mutation", resource, key), **body}
        status, data = api.call("POST", f"{base}/{resource}", body)
        if 200 <= status < 300:
            return
        # A re-run on a later day sends the same record with newer dates; the
        # server keeps the first copy and refuses the changed replay. That
        # record is already seeded, which is all this script needs.
        code = data.get("error", {}).get("code") if isinstance(data, dict) else None
        if status == 409 and code == "mutation_conflict":
            return
        raise SystemExit(f"POST {base}/{resource} failed: HTTP {status} {data}")

    # Near KwaMashu, KwaZulu-Natal. Only Cabbage Field has been walked.
    sections = {
        "Cabbage Field": ("5000.00", square(-29.7442, 30.9875, 70, 72)),
        "Tomato Section": ("3000.00", None),
        "North Plot": ("4000.00", None),
        "Spinach Beds": ("2000.00", None),
    }
    ids = {name: stable_id("section", name) for name in sections}
    for name, (area, boundary) in sections.items():
        body: dict[str, Any] = {"id": ids[name], "name": name, "area_m2": area}
        if boundary is not None:
            body["boundary"] = boundary
        post("sections", name, body)

    plantings = {
        "Cabbage Field": ("cabbage", 62),
        "Tomato Section": ("tomatoes", 45),
        "Spinach Beds": ("spinach", 21),
        # North Plot stays empty: the "what should I plant here?" section.
    }
    for name, (crop, days_ago) in plantings.items():
        post(
            "plantings",
            name,
            {
                "id": stable_id("planting", name),
                "section_id": ids[name],
                "crop": crop,
                "planted_on": (today - timedelta(days=days_ago)).isoformat(),
                "is_current": True,
            },
        )

    tasks = [
        ("Cabbage Field", "Weeding", -4, "pending", 30000),
        ("Tomato Section", "Stake and tie the tomatoes", 2, "pending", 45000),
        ("Spinach Beds", "Water the spinach", 1, "pending", None),
        ("Cabbage Field", "Side-dress with fertiliser", 9, "pending", 120000),
        ("Spinach Beds", "Thin the seedlings", -6, "done", None),
    ]
    for section, title, due_in, status, cost in tasks:
        post(
            "tasks",
            f"{section}/{title}",
            {
                "id": stable_id("task", section, title),
                "section_id": ids[section],
                "title": title,
                "due_date": (today + timedelta(days=due_in)).isoformat(),
                "status": status,
                "expected_cost_cents": cost,
            },
        )

    # Mid-morning today (UTC), so a re-run the same day sends identical checks.
    now = datetime.combine(today, time(8, 0), tzinfo=UTC)
    observations = [
        ("Cabbage Field", "General check", "on_track", "Heads forming well, no pests seen.", 5),
        (
            "Tomato Section",
            "Leaf curl",
            "needs_attention",
            "Lower leaves curling on the east rows. Could be heat or aphids.",
            2,
        ),
        ("Spinach Beds", "General check", "on_track", "Good colour, first leaves nearly ready.", 1),
    ]
    for section, kind, health, note, days_ago in observations:
        post(
            "observations",
            f"{section}/{kind}",
            {
                "observation_id": stable_id("observation", section, kind),
                "section_id": ids[section],
                "type": kind,
                "note": note,
                "health_status": health,
                "created_at": (now - timedelta(days=days_ago)).isoformat(),
            },
        )

    financials = [
        ("expense", "seed", 85000, "Cabbage Field", "Cabbage seedlings", 63),
        ("expense", "fertiliser", 120000, "Cabbage Field", "LAN and 2:3:2", 40),
        ("expense", "seed", 64000, "Tomato Section", "Tomato seedlings", 46),
        ("expense", "labour", 60000, None, "Weeding help, two days", 12),
        ("income", "sale", 240000, "Spinach Beds", "Spinach bunches at the market", 3),
    ]
    for kind, category, cents, where, note, days_ago in financials:
        post(
            "financials",
            f"{kind}/{note}",
            {
                "id": stable_id("financial", kind, note),
                "type": kind,
                "category": category,
                "amount_cents": cents,
                "date": (today - timedelta(days=days_ago)).isoformat(),
                "section_id": ids[where] if where else None,
                "note": note,
            },
        )
    print(
        f"Seeded {FARM_NAME}: {len(sections)} sections, {len(plantings)} plantings, "
        f"{len(tasks)} tasks, {len(observations)} checks, {len(financials)} money records"
    )


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    parser.add_argument("--api", default="http://127.0.0.1:8000")
    parser.add_argument(
        "--existing",
        metavar="EMAIL_OR_PHONE",
        help="log into this existing account instead of signing up the local one",
    )
    args = parser.parse_args(argv)
    local = args.api.startswith(("http://127.0.0.1", "http://localhost"))
    api = Api(args.api)
    if args.existing:
        if not (local or args.api.startswith("https://")):
            raise SystemExit("Use https for a remote API.")
        log_in_existing(api, args.existing)
    elif local:
        sign_in(api)
    else:
        raise SystemExit(
            "Sign-up with the fixed fake codes is local only. For a real account "
            "that already exists, pass --existing EMAIL_OR_PHONE."
        )
    seed(api, date.today())
    if not args.existing:
        # The fixed local password is in the README; never echo a credential.
        print(f"Log in on the phone as {DEMO_EMAIL} (password: see the README)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
