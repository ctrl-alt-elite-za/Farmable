"""Three real local-HTTP journeys, not full #26/browser/production readiness."""

import json
import socket
import threading
import time
from pathlib import Path
from tempfile import TemporaryDirectory
from typing import Any
from uuid import uuid4

import httpx
import uvicorn

from .app import create_demo_app
from .storage import initialize_storage


def check(condition: bool, message: str) -> None:
    if not condition:
        raise RuntimeError(message)


def journey(client: httpx.Client) -> dict[str, Any]:
    response = client.post("/demo/sessions", json={})
    check(response.status_code == 201, "Could not create synthetic demo session")
    session = response.json()
    auth = {"Authorization": "Bearer " + session["access_token"]}
    section = next(s for s in session["dashboard"]["sections"] if s["current_crop"] is None)
    controls = {"planting_date": "2026-09-18", "budget_cents": 300_000}

    def write(route: str, payload: dict) -> dict:
        result = client.post(route, json=payload, headers={**auth, "Idempotency-Key": str(uuid4())})
        check(result.status_code in (200, 201), "Local demo write failed")
        return result.json()

    preview = client.post(f"/demo/sections/{section['id']}/preview", json=controls, headers=auth)
    check(preview.status_code == 200 and preview.json()["feasible"], "Baseline preview failed")
    baseline = write(f"/demo/sections/{section['id']}/plans", controls)
    half = write(
        f"/demo/plans/{baseline['id']}/constraints",
        {
            **controls,
            "min_crop_shares": [{"crop": "cabbage", "percent": 50}],
        },
    )
    check(
        half["result"]["plans"][0]["blocks"] == ["cabbage", "cabbage", "spinach", "spinach"],
        "Half-cabbage constraint failed",
    )
    tight_controls = {
        **controls,
        "budget_cents": 210_000,
        "min_crop_shares": [{"crop": "cabbage", "percent": 50}],
    }
    tight = write(f"/demo/plans/{half['id']}/constraints", tight_controls)
    check(
        tight["result"]["plans"][0]["blocks"] == ["cabbage", "cabbage", "spinach", None],
        "Budget fitting failed",
    )
    approved = write(f"/demo/plans/{tight['id']}/approve", {})
    reopened = client.get(f"/demo/plans/{tight['id']}", headers=auth)
    check(reopened.status_code == 200 and reopened.json() == approved, "Reopen failed")
    board = client.get("/demo/farm", headers=auth)
    check(
        board.status_code == 200 and board.json()["approved_plans"][0]["id"] == approved["id"],
        "Dashboard did not show the approved plan",
    )
    impossible = client.post(
        f"/demo/sections/{section['id']}/preview",
        json={**tight_controls, "budget_cents": 100_000},
        headers=auth,
    )
    check(
        impossible.status_code == 200 and not impossible.json()["feasible"],
        "Impossible budget was not explained",
    )
    unsupported = client.post(
        f"/demo/sections/{section['id']}/preview",
        json={**controls, "planting_date": "2026-10-01"},
        headers=auth,
    )
    check(
        unsupported.status_code == 200
        and unsupported.json()["reason"]["code"] == "unsupported_date",
        "Unsupported date was not explained",
    )
    return {"result": "pass", "scope": "local synthetic API; no browser or voice rehearsal"}


def main() -> None:
    # Own a temporary store/server; no child interpreter launchers or orphan processes.
    with TemporaryDirectory(prefix="farmable-api-rehearsal-") as temporary:
        path = Path(temporary) / "state.sqlite3"
        initialize_storage(path)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
            server = uvicorn.Server(
                uvicorn.Config(
                    create_demo_app(path, origins=("http://localhost:5173",)),
                    host="127.0.0.1",
                    port=port,
                    log_config=None,
                    access_log=False,
                    timeout_graceful_shutdown=3,
                )
            )
            worker = threading.Thread(
                target=server.run, kwargs={"sockets": [listener]}, daemon=True
            )
            worker.start()
            try:
                deadline = time.monotonic() + 10
                while not server.started:
                    if not worker.is_alive():
                        raise RuntimeError("Local demo helper stopped before readiness")
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Local demo helper did not start")
                    time.sleep(0.1)
                with httpx.Client(
                    base_url=f"http://127.0.0.1:{port}", timeout=5, trust_env=False
                ) as client:
                    reports = [{"run": run, **journey(client)} for run in range(1, 4)]
            finally:
                server.should_exit = True
                worker.join(timeout=5)
                check(not worker.is_alive(), "Local demo helper did not shut down")
    # Print passing evidence only after server, DB handles and temporary storage are closed.
    print(json.dumps(reports, indent=2))


if __name__ == "__main__":
    main()
