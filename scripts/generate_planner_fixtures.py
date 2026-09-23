"""Capture reference vectors from the Python planner for the Dart port to match.

``apps/backend/src/farmable_backend/planning/`` is the oracle. The Flutter app
carries its own copy of that arithmetic so a farmer can ask "what should I
plant?" with no network (issue #22), and a second implementation of money is a
second chance to be wrong about it. So the Dart planner is not reviewed against
the Python by reading both: it is run over the vectors this script captures and
asserted equal, field by field, in ``test/planner_oracle_test.dart``.

The responses are taken from ``POST /demo/sections/{id}/preview`` rather than
from ``plan_section`` directly, because the wire is where the Dart client
actually meets this data, and the wire is where ``Decimal`` becomes a *string*
with significant trailing zeros.

Run with ``uv run python scripts/generate_planner_fixtures.py`` from the repo
root. It starts its own demo API on disposable storage; no developer database
and no already-running server is used.
"""

import json
import os
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Any
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
FIXTURES = ROOT / "apps/mobile/test/fixtures/planner"

# Areas the vectors plan over. Each becomes one demo section; the preview
# endpoint reads the area from the section, so varying it means varying these.
AREAS = {
    "north_plot": "7000.00",
    "demo": "400.00",
    "smallest": "1.00",
    "largest": "1000000.00",
    "thirds": "333.33",
}

BOTH = ["cabbage", "spinach"]

# Each vector states *why* it exists. A vector nobody can justify is a vector
# nobody will fix when it breaks.
VECTORS: tuple[dict[str, Any], ...] = (
    {
        "name": "north_plot_baseline",
        "note": "The app's own entry point: North Plot, 0.7 ha, planting now.",
        "area": "north_plot",
        "request": {"planting_date": "2026-09-18", "budget_cents": 6_000_000},
    },
    {
        "name": "demo_normal",
        "note": "planning/demo.py 'normal' - the unconstrained baseline.",
        "area": "demo",
        "request": {"planting_date": "2026-09-18", "budget_cents": 300_000},
    },
    {
        "name": "demo_keep_half_cabbage",
        "note": "The issue #22 constraint flow: 'keep at least half as cabbage'.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            "min_crop_shares": [{"crop": "cabbage", "percent": 50}],
        },
    },
    {
        "name": "demo_tight_budget",
        "note": "Half cabbage still affordable, but only just - the plan changes.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 210_000,
            "min_crop_shares": [{"crop": "cabbage", "percent": 50}],
        },
    },
    {
        "name": "budget_affords_nothing",
        "note": "Edge: zero budget. Infeasible, and must carry the minimum required.",
        "area": "demo",
        "request": {"planting_date": "2026-09-18", "budget_cents": 0},
    },
    {
        "name": "budget_affords_exactly_one_block",
        "note": "Edge: R600 buys one spinach block of 100 m2 and nothing else.",
        "area": "demo",
        "request": {"planting_date": "2026-09-18", "budget_cents": 60_000, "max_results": 10},
    },
    {
        "name": "budget_one_cent_short",
        "note": "Edge: one cent below the cheapest planted block. Still infeasible.",
        "area": "demo",
        "request": {"planting_date": "2026-09-18", "budget_cents": 59_999},
    },
    {
        "name": "minimum_share_exceeds_budget",
        "note": "Infeasible for a *different* reason than budget alone - the share.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 100_000,
            "min_crop_shares": [{"crop": "cabbage", "percent": 50}],
        },
    },
    {
        "name": "minimum_share_cannot_fit_blocks",
        "note": "Edge: two 50% shares over one block. No cost exists to report.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            "block_count": 1,
            "min_crop_shares": [
                {"crop": "cabbage", "percent": 50},
                {"crop": "spinach", "percent": 50},
            ],
        },
    },
    {
        "name": "conflicting_minimum_shares",
        "note": "Shares summing over 100 are refused before any allocation is tried.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            "min_crop_shares": [
                {"crop": "cabbage", "percent": 60},
                {"crop": "spinach", "percent": 50},
            ],
        },
    },
    {
        "name": "zero_minimum_share_budget_too_low",
        "note": "A 0% share is not a minimum: the refusal is budget_too_low, not share.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 50_000,
            "min_crop_shares": [{"crop": "cabbage", "percent": 0}],
        },
    },
    {
        "name": "unsupported_date_after",
        "note": "October. The scenario covers September 2026 only and must refuse.",
        "area": "demo",
        "request": {"planting_date": "2026-10-01", "budget_cents": 300_000},
    },
    {
        "name": "unsupported_date_before",
        "note": "The day before the window opens.",
        "area": "demo",
        "request": {"planting_date": "2026-08-31", "budget_cents": 300_000},
    },
    {
        "name": "planting_window_first_day",
        "note": "The window is inclusive at both ends.",
        "area": "demo",
        "request": {"planting_date": "2026-09-01", "budget_cents": 300_000},
    },
    {
        "name": "planting_window_last_day",
        "note": "The window is inclusive at both ends.",
        "area": "demo",
        "request": {"planting_date": "2026-09-30", "budget_cents": 300_000},
    },
    {
        "name": "smallest_supported_area",
        "note": "Edge: 1 m2 over four blocks. Quarter-square-metre allocations.",
        "area": "smallest",
        "request": {"planting_date": "2026-09-18", "budget_cents": 300_000, "max_results": 10},
    },
    {
        "name": "largest_supported_area",
        "note": "Edge: a million m2 against the largest budget the schema allows.",
        "area": "largest",
        "request": {
            "planting_date": "2026-09-15",
            "budget_cents": 1_000_000_000,
            "max_results": 10,
        },
    },
    {
        "name": "largest_area_tight_budget",
        "note": "A million m2 where only the cheaper crop fits - big integer cents.",
        "area": "largest",
        "request": {"planting_date": "2026-09-15", "budget_cents": 620_000_000},
    },
    {
        "name": "recurring_thirds",
        "note": "Three blocks over 400 m2: the division recurs and must not drift.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            "block_count": 3,
            "max_results": 10,
        },
    },
    {
        "name": "recurring_thirds_exact",
        "note": "333.33 over three blocks divides exactly. The exponent must survive.",
        "area": "thirds",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            "block_count": 3,
            "max_results": 10,
        },
    },
    {
        "name": "one_block_whole_section",
        "note": "block_count 1: the whole section, or nothing planted at all.",
        "area": "demo",
        "request": {"planting_date": "2026-09-18", "budget_cents": 300_000, "block_count": 1},
    },
    {
        "name": "two_blocks_single_crop",
        "note": "One crop selected. The other must not appear anywhere in the result.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            "crops": ["spinach"],
            "block_count": 2,
            "max_results": 10,
        },
    },
    {
        "name": "single_crop_minimum_three_quarters",
        "note": "A 75% share over four blocks needs three of them.",
        "area": "demo",
        "request": {
            "planting_date": "2026-09-18",
            "budget_cents": 300_000,
            "crops": ["cabbage"],
            "min_crop_shares": [{"crop": "cabbage", "percent": 75}],
            "max_results": 10,
        },
    },
    {
        "name": "all_candidates_max_results",
        "note": "max_results 10 returns every distinct allocation, in ranked order.",
        "area": "demo",
        "request": {"planting_date": "2026-09-18", "budget_cents": 300_000, "max_results": 10},
    },
    {
        "name": "north_plot_minimum_three_quarters_cabbage",
        "note": "The constraint flow at the real section area, early in the window.",
        "area": "north_plot",
        "request": {
            "planting_date": "2026-09-05",
            "budget_cents": 100_000_000,
            "min_crop_shares": [{"crop": "cabbage", "percent": 75}],
            "max_results": 10,
        },
    },
    {
        "name": "north_plot_leaves_land_idle",
        "note": "A budget that plants some of North Plot and honestly leaves the rest.",
        "area": "north_plot",
        "request": {"planting_date": "2026-09-18", "budget_cents": 2_700_000, "max_results": 10},
    },
)


def _call(
    base: str, method: str, path: str, token: str | None, body: Any, key: str | None = None
) -> Any:
    headers = {"Content-Type": "application/json"}
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if key:
        headers["Idempotency-Key"] = key
    request = Request(  # noqa: S310 - loopback URL built from our own socket
        base + path,
        method=method,
        data=json.dumps(body).encode(),
        headers=headers,
    )
    try:
        with urlopen(request, timeout=20) as response:  # noqa: S310 - as above
            return json.loads(response.read())
    except HTTPError as error:
        raise RuntimeError(f"{method} {path} failed: {error.read().decode()}") from error


def capture(base: str) -> None:
    session = _call(base, "POST", "/demo/sessions", None, {})
    token = session["access_token"]

    sections = {}
    for label, area in AREAS.items():
        created = _call(
            base,
            "POST",
            "/demo/sections",
            token,
            {"name": f"fixture-{label}", "area_m2": area},
            key=f"fixture-{label}",
        )
        if created["area_m2"] != area:
            raise RuntimeError(f"Section {label} came back as {created['area_m2']}, wanted {area}")
        sections[label] = created["id"]

    FIXTURES.mkdir(parents=True, exist_ok=True)
    for stale in FIXTURES.glob("*.json"):
        stale.unlink()

    written = []
    for vector in VECTORS:
        # Spelled out in full rather than left to the server's defaults: a
        # fixture the Dart side has to guess the inputs of proves nothing.
        request = {
            "crops": BOTH,
            "block_count": 4,
            "min_crop_shares": [],
            "max_results": 3,
            **vector["request"],
        }
        section_id = sections[vector["area"]]
        response = _call(base, "POST", f"/demo/sections/{section_id}/preview", token, request)
        # The demo API mints a fresh UUID per section, so echoing it back would
        # make every regeneration rewrite every file and bury a real change in
        # the diff. The planner treats section_id as an opaque correlation id
        # and computes nothing from it, so naming it after the area loses
        # nothing and keeps the fixtures reproducible.
        response["request"]["section_id"] = f"fixture-{vector['area']}"
        document = {
            "name": vector["name"],
            "note": vector["note"],
            "area_m2": AREAS[vector["area"]],
            "request": request,
            "response": response,
        }
        path = FIXTURES / f"{vector['name']}.json"
        path.write_text(json.dumps(document, indent=2) + "\n", encoding="utf-8")
        written.append(vector["name"])
        feasible = response["feasible"]
        outcome = f"{len(response['plans'])} plans" if feasible else response["reason"]["code"]
        print(f"  {vector['name']:<42} {outcome}")

    index = FIXTURES / "index.json"
    index.write_text(json.dumps(written, indent=2) + "\n", encoding="utf-8")
    print(f"\n{len(written)} vectors written to {FIXTURES.relative_to(ROOT).as_posix()}")


def main() -> int:
    if len({vector["name"] for vector in VECTORS}) != len(VECTORS):
        raise RuntimeError("Vector names must be unique - they are the fixture filenames")

    with tempfile.TemporaryDirectory(
        prefix="farmable-planner-fixtures-", ignore_cleanup_errors=True
    ) as directory:
        env = {**os.environ, "FARMABLE_DEMO_DB": str(Path(directory) / "state.sqlite3")}
        subprocess.run(  # noqa: S603 - fixed module and arguments, no shell
            [sys.executable, "-m", "farmable_backend.demo_api.init"],
            cwd=ROOT,
            env=env,
            check=True,
            timeout=60,
        )
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            port = listener.getsockname()[1]
            base = f"http://127.0.0.1:{port}"
            # Windows cannot inherit a socket into a child, so hand over the
            # port instead. Same trade-off as scripts/test_mobile_contract.py.
            inherit = os.name != "nt"
            command = [
                sys.executable,
                "-m",
                "uvicorn",
                "farmable_backend.demo_api.app:app",
                "--no-access-log",
            ]
            if inherit:
                command += ["--fd", str(listener.fileno())]
            else:
                listener.close()
                command += ["--host", "127.0.0.1", "--port", str(port)]

            server = subprocess.Popen(  # noqa: S603 - fixed module and arguments
                command,
                cwd=ROOT,
                env=env,
                pass_fds=(listener.fileno(),) if inherit else (),
            )
            try:
                deadline = time.monotonic() + 60
                while True:
                    if server.poll() is not None:
                        raise RuntimeError("Demo API exited before becoming ready")
                    try:
                        with urlopen(base + "/health/live", timeout=1) as ready:  # noqa: S310
                            if ready.status == 200:
                                break
                    except (URLError, TimeoutError):
                        pass
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Demo API did not become ready within 60 seconds")
                    time.sleep(0.1)
                capture(base)
            finally:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=10)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
