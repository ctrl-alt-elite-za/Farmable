"""No paid calls: real ORM/API path over an explicitly synthetic active snapshot."""

import json
from datetime import UTC, date, datetime
from decimal import ROUND_DOWN, Context, Decimal, localcontext
from time import perf_counter
from types import SimpleNamespace
from uuid import UUID, uuid4

import pytest
from farmable_backend.assistant.tools import execute
from farmable_backend.forecast_contract import CROPS, ForecastBundle
from farmable_backend.forecasts import import_bundle
from farmable_backend.models import (
    Farm,
    ForecastRun,
    ForecastState,
    SavedPlan,
    Section,
    SyncChange,
    SyncMutation,
)
from farmable_backend.planning import service
from farmable_backend.planning.calendar import add_months, holidays, payment_date
from farmable_backend.planning.contracts import PlanRequest
from farmable_backend.planning.production import calculate, estimate
from farmable_backend.record_access import ApiError
from sqlalchemy import func, select
from test_assistant import assistant as assistant_fixture
from test_assistant import post, script, wire
from test_forecasts import bundle, raw

assistant = assistant_fixture


@pytest.fixture
def planner(assistant, monkeypatch):
    with assistant.sessions.begin() as session:
        session.add(ForecastState(id=1))
    import_bundle(assistant.sessions, "sample-v1", raw(bundle()), "sample")
    assistant.client.app.state.forecast_data_mode = "sample"
    assistant.runtime.mode = "sample"
    monkeypatch.setattr(service, "db_now", lambda _: datetime(2026, 9, 23, tzinfo=UTC))
    return assistant


def request(planner, **changes):
    return {
        "section_id": str(planner.alice.section),
        "planting_date": "2026-10-01",
        "budget_cents": 1_000_000,
        "money_basis_year": 2025,
        "crops": [{"crop": "cabbage"}, {"crop": "spinach"}],
        "planting_cost_percent": 50,
        "market_commission_bps": 500,
        "agent_commission_bps": 250,
        **changes,
    }


def preview(planner, **changes):
    return planner.client.post(
        f"/farms/{planner.alice.farm}/planning/preview",
        headers={"Authorization": planner.alice.auth},
        json=request(planner, **changes),
    )


def confirmation(view, **changes):
    return {
        "mutation_id": str(uuid4()),
        "plan_id": str(uuid4()),
        "confirmed": True,
        "request": view["request"],
        "snapshot_hash": view["snapshot_hash"],
        "candidate_id": view["candidates"][0]["id"],
        **changes,
    }


def confirm(planner, payload):
    return planner.client.post(
        f"/farms/{planner.alice.farm}/planning/confirm",
        headers={"Authorization": planner.alice.auth},
        json=payload,
    )


def test_preview_is_read_only_deterministic_and_grounded(planner):
    response = preview(planner)
    assert response.status_code == 200 and response.headers["cache-control"] == "no-store"
    view = response.json()
    assert preview(planner).json() == view
    assert view["source"]["data_kind"] == "synthetic" and view["source"]["warning"]
    assert view["source"]["run_id"] == "sample-v1"
    assert view["source"]["weather"]["cabbage"]["status"] == "unavailable"
    assert all(
        c["required_cash_cents"] <= view["request"]["budget_cents"] for c in view["candidates"]
    )
    for plan in view["candidates"]:
        costs = sum(a["production_cost_cents"] for a in plan["allocations"])
        receipts = sum(a["sales_cents"] - a["commission_cents"] for a in plan["allocations"])
        assert plan["margin_cents"] == receipts - costs
        assert sum(e["cost_cents"] for e in plan["cash_timeline"]) == costs
        assert plan["cash_timeline"][-1]["balance_cents"] == 1_000_000 + plan["margin_cents"]
        assert min(e["balance_cents"] for e in plan["cash_timeline"]) >= 0
    with planner.sessions() as session:
        assert session.scalar(select(func.count()).select_from(SavedPlan)) == 0
        assert session.scalar(select(func.count()).select_from(SyncMutation)) == 0


def test_confirm_sync_read_export_retry_and_version_conflict(planner):
    view = preview(planner).json()
    payload = confirmation(view)
    response = confirm(planner, payload)
    assert response.status_code == 200 and response.json()["version"] == 1
    assert confirm(planner, payload).json()["replayed"] is True
    with planner.sessions() as session:
        saved = session.get(SavedPlan, UUID(payload["plan_id"]))
        assert saved.status == "approved" and saved.approved_at is not None
        assert saved.plan["candidate"]["id"] == payload["candidate_id"]
        assert session.scalar(select(func.count()).select_from(SyncMutation)) == 1
        assert session.scalar(select(func.count()).select_from(SyncChange)) == 1
    assert confirm(planner, {**payload, "mutation_id": str(uuid4())}).status_code == 409
    updated = {**payload, "mutation_id": str(uuid4()), "expected_version": 1}
    assert confirm(planner, updated).json()["version"] == 2
    assert confirm(planner, payload).json()["error"]["code"] == "plan_state_changed"
    from farmable_backend.account import AccountService

    account = AccountService(planner.sessions)
    account.set_consent(planner.alice.auth, "data_export", "1", True)
    exported = account.export_document(planner.alice.auth)
    assert exported["saved_plans"][0]["plan"]["snapshot_hash"] == view["snapshot_hash"]
    read = planner.client.get(
        f"/farms/{planner.alice.farm}/plans/{payload['plan_id']}",
        headers={"Authorization": planner.alice.auth},
    )
    assert read.status_code == 200 and read.json()["version"] == 2


@pytest.mark.parametrize("change", ["area", "version", "boundary", "forecast", "mode", "deleted"])
def test_stale_preview_is_never_committed(planner, change):
    payload = confirmation(preview(planner).json())
    with planner.sessions.begin() as session:
        section = session.get(Section, planner.alice.section)
        if change == "area":
            section.area_m2 += 1
        elif change == "version":
            section.version += 1
        elif change == "boundary":
            section.boundary = {"changed": True}
        elif change == "deleted":
            section.deleted_at = datetime.now(UTC)
        elif change == "forecast":
            run = session.get(ForecastRun, "sample-v1")
            value = json.loads(json.dumps(run.payload))
            value["rows"][0]["p50"] = "8"
            run.payload = value
    if change == "mode":
        planner.client.app.state.forecast_data_mode = "historical"
    assert confirm(planner, payload).status_code in {404, 409, 503}
    with planner.sessions() as session:
        assert session.scalar(select(func.count()).select_from(SavedPlan)) == 0


def test_explicit_confirmation_tampering_and_deleted_retry(planner):
    payload = confirmation(preview(planner).json())
    for value in [False, "true", 1]:
        assert confirm(planner, {**payload, "confirmed": value}).status_code == 422
    assert confirm(planner, {**payload, "candidate_id": "0" * 64}).status_code == 409
    changed = {**payload, "request": {**payload["request"], "budget_cents": 2_000_000}}
    assert confirm(planner, changed).json()["error"]["code"] == "plan_stale"
    assert confirm(planner, payload).status_code == 200
    assert confirm(planner, changed).json()["error"]["code"] == "mutation_conflict"
    with planner.sessions.begin() as session:
        session.get(SavedPlan, UUID(payload["plan_id"])).deleted_at = datetime.now(UTC)
    assert confirm(planner, payload).json()["error"]["code"] == "record_deleted"


def test_scope_and_no_outlook_fail_closed(planner):
    assert preview(planner, section_id=str(planner.bob.section)).status_code == 404
    response = planner.client.post(
        f"/farms/{planner.alice.farm}/planning/preview",
        headers={"Authorization": planner.bob.auth},
        json=request(planner),
    )
    assert response.status_code == 404
    otherfarm, othersection = uuid4(), uuid4()
    with planner.sessions.begin() as session:
        session.add(Farm(id=otherfarm, owner_id=planner.alice.owner, name="Other"))
        session.flush()
        session.add(
            Section(
                id=othersection,
                farm_id=otherfarm,
                owner_id=planner.alice.owner,
                name="Other",
                area_m2=100,
            )
        )
    assert execute(
        planner.store,
        planner.alice.auth,
        planner.conversation,
        "preview_planting_plan",
        request(planner, section_id=str(othersection)),
        "sample",
    ) == {"error": "not_found"}
    with planner.sessions.begin() as session:
        session.get(ForecastState, 1).active_run_id = None
    assert preview(planner).json()["error"]["code"] == "outlook_unavailable"


@pytest.mark.parametrize(
    "fields",
    [
        {"budget_cents": True},
        {"block_count": 5},
        {"max_results": 6},
        {"money_basis_year": 2026},
        {"crops": [{"crop": "cabbage"}, {"crop": "cabbage"}]},
        {"market_commission_bps": 5000, "agent_commission_bps": 5000},
        {"planting_date": "2020-01-01"},
        {"area_m2": 9999},
        {"owner_id": str(uuid4())},
    ],
)
def test_invalid_or_untrusted_inputs(planner, fields):
    assert preview(planner, **fields).status_code == 422


def test_budget_goal_promises_and_deadline_constraints(planner):
    assert preview(planner, budget_cents=0).json()["change_needed"]["code"] == "budget_too_low"
    deadline = preview(planner, cash_deadline="2026-10-02").json()
    assert not deadline["feasible"] and deadline["change_needed"]
    impossible = preview(
        planner,
        crops=[
            {"crop": "cabbage", "minimum_percent": 75},
            {"crop": "spinach", "minimum_percent": 75},
        ],
    ).json()
    assert not impossible["feasible"]
    promised = preview(planner, crops=[{"crop": "cabbage", "promised_kg": "1000000"}]).json()
    assert not promised["feasible"]
    result = preview(
        planner,
        crops=[{"crop": "cabbage", "minimum_percent": 50}, {"crop": "spinach"}],
        goal_margin_cents=100,
    ).json()
    assert result["feasible"]
    for value in result["candidates"]:
        assert value["margin_cents"] >= 100
        assert next(a for a in value["allocations"] if a["crop"] == "cabbage")["blocks"] >= 2
    costs = [p["required_cash_cents"] for p in result["candidates"]]
    assert costs == sorted(costs)


def test_assistant_previews_but_cannot_confirm_or_grant_itself_authority(planner):
    args = request(planner, max_results=1)
    calls = script(
        planner,
        [
            [wire([{"functionCall": {"name": "preview_planting_plan", "args": args}}])],
            [wire([{"text": "Please review this preview in the app."}])],
        ],
    )
    response, events, _ = post(planner)
    assert response.status_code == 200 and events[-1]["type"] == "done"
    assert len(calls) == 2 and any(e["type"] == "tool" for e in events)
    assert execute(
        planner.store,
        planner.alice.auth,
        planner.conversation,
        "confirm_planting_plan",
        {"confirmed": True},
        "sample",
    ) == {"error": "tool_not_allowed"}
    with planner.sessions() as session:
        assert session.scalar(select(func.count()).select_from(SavedPlan)) == 0
    planner.store.consent(planner.alice.auth, planner.conversation, withdraw=True)
    with pytest.raises(ApiError) as error:
        execute(
            planner.store,
            planner.alice.auth,
            planner.conversation,
            "preview_planting_plan",
            args,
            "sample",
        )
    assert error.value.status == 403


def test_calendar_holidays_year_rollover_and_unsupported_horizon():
    assert payment_date(date(2026, 4, 1)) == date(2026, 4, 10)
    assert payment_date(date(2026, 12, 24)) == date(2027, 1, 4)
    assert payment_date(date(2026, 10, 30)) == date(2026, 11, 9)
    assert date(2026, 8, 10) in holidays(2026)
    assert date(2027, 12, 27) in holidays(2027)
    assert add_months(date(2026, 1, 31), 1) == date(2026, 2, 28)
    with pytest.raises(ApiError, match="calendar_unavailable"):
        payment_date(date(2027, 12, 31))


def test_all_crops_bounded_performance_and_decimal_context(planner):
    value = PlanRequest.model_validate(request(planner, crops=[{"crop": crop} for crop in CROPS]))
    rows = {
        row.crop: row
        for row in ForecastBundle.model_validate(bundle()).rows
        if row.plant_month == 10
    }
    section = SimpleNamespace(area_m2=Decimal("1000"), version=1)
    start = perf_counter()
    result = calculate(value, section, rows, {})
    assert perf_counter() - start < 1
    with localcontext(Context(prec=6, rounding=ROUND_DOWN)):
        assert calculate(value, section, rows, {}) == result


def test_recurring_thirds_round_once_and_cost_timing_is_exact(planner):
    value = PlanRequest.model_validate(
        request(
            planner,
            block_count=3,
            market_commission_bps=0,
            agent_commission_bps=0,
            planting_cost_percent=0,
        )
    )
    row = (
        ForecastBundle.model_validate(bundle())
        .rows[0]
        .model_copy(
            update={"cost_per_ha": Decimal(150), "yield_kg_per_ha": Decimal(1), "p50": Decimal(150)}
        )
    )
    result = estimate(row, Decimal(1), 1, value)
    assert result.production_cost_cents == 1 and result.sales_cents == 1
    assert sum(amount for _, amount in result.cost_schedule) == 1
    assert result.cost_schedule[0] == (value.planting_date, 0)
    assert all(day > value.planting_date for day, _ in result.cost_schedule[1:])


def test_weather_change_invalidates_preview_and_replay_does_not_need_outlook(planner, monkeypatch):
    payload = confirmation(preview(planner).json())
    original = service.cached_weather
    monkeypatch.setattr(
        service,
        "cached_weather",
        lambda *args: SimpleNamespace(
            model_dump=lambda **kwargs: {"status": "unavailable", "changed": True}
        ),
    )
    assert confirm(planner, payload).json()["error"]["code"] == "plan_stale"
    monkeypatch.setattr(service, "cached_weather", original)
    assert confirm(planner, payload).status_code == 200
    planner.client.app.state.forecast_data_mode = "disabled"
    assert confirm(planner, payload).json()["replayed"] is True


def test_no_sample_fallback_in_historical_mode(planner):
    planner.client.app.state.forecast_data_mode = "historical"
    assert preview(planner).json()["error"]["code"] == "outlook_unavailable"
    # Synthetic test values labelled as historical exercise the mode gate only;
    # they are not evidence that any live dataset meets production acceptance.
    with planner.sessions.begin() as session:
        run = session.get(ForecastRun, "sample-v1")
        value = json.loads(json.dumps(run.payload))
        value["data_kind"] = "historical"
        for row in value["rows"]:
            row["method"] = "historical_range"
        run.payload = value
    response = preview(planner)
    assert response.status_code == 200 and response.json()["source"]["data_kind"] == "historical"


def test_unrepresentable_money_is_refused_instead_of_rounded_by_clients(planner):
    value = PlanRequest.model_validate(request(planner))
    row = (
        ForecastBundle.model_validate(bundle())
        .rows[0]
        .model_copy(update={"yield_kg_per_ha": Decimal("9999999999"), "p50": Decimal("9999999999")})
    )
    with pytest.raises(ApiError, match="outlook_unavailable"):
        estimate(row, Decimal("1000000"), 4, value)
