"""Offline pricing/receipt/import tests; example rates are deliberately synthetic."""

import copy
import io
import json
from datetime import UTC, date, datetime, timedelta
from uuid import uuid4

import pytest
from alembic import command
from alembic.config import Config
from farmable_backend.account import AccountService
from farmable_backend.assistant import accounting
from farmable_backend.assistant.pricing import TextPricePolicy, price_usage
from farmable_backend.assistant.reconcile import (
    ReconciliationError,
    compare,
    export_totals,
    ledger_totals,
)
from farmable_backend.assistant.schemas import TurnCreate
from farmable_backend.auth import PASSWORD_HASHER
from farmable_backend.models import (
    AssistantBudget,
    AssistantModelCall,
    AssistantTurnCost,
    AuthIdentity,
)
from farmable_backend.record_access import ApiError
from sqlalchemy import select
from test_assistant import assistant as assistant_fixture
from test_assistant import post, script, wire
from test_farm_schema import _index_statements, _orm_sql, _table_elements

assistant = assistant_fixture


def pricing():
    today = date.today()
    return TextPricePolicy(
        model="fixture-model",
        response_models=["fixture-version"],
        valid_from=today - timedelta(days=1),
        valid_until=today + timedelta(days=1),
        input_micro_usd_per_million=1_000_000,
        cached_input_micro_usd_per_million=100_000,
        output_micro_usd_per_million=2_000_000,
        max_prompt_tokens=1000,
    )


def usage():
    return {
        "promptTokenCount": 100,
        "cachedContentTokenCount": 20,
        "candidatesTokenCount": 10,
        "thoughtsTokenCount": 5,
        "totalTokenCount": 115,
    }


def test_prices_cached_input_and_thinking_once_with_integer_rounding():
    assert price_usage(
        pricing(), "fixture-model", "fixture-version", date.today(), usage(), complete=True
    ) == (112, None)
    rates = pricing().model_copy(update={"input_micro_usd_per_million": 1})
    assert price_usage(
        rates,
        "fixture-model",
        "fixture-version",
        date.today(),
        {"promptTokenCount": 1, "candidatesTokenCount": 0, "totalTokenCount": 1},
        complete=True,
    ) == (1, None)


@pytest.mark.parametrize(
    "change", ["missing", "inconsistent", "cached", "bool", "tier", "model", "stale", "partial"]
)
def test_unknown_or_unsupported_usage_is_not_zero_cost(change):
    values, policy, model, complete = usage(), pricing(), "fixture-version", True
    if change == "missing":
        del values["candidatesTokenCount"]
    elif change == "inconsistent":
        values["totalTokenCount"] += 1
    elif change == "cached":
        values["cachedContentTokenCount"] = 101
    elif change == "bool":
        values["thoughtsTokenCount"] = True
    elif change == "tier":
        policy.max_prompt_tokens = 99
    elif change == "model":
        model = "different-version"
    elif change == "stale":
        policy.valid_until = date.today() - timedelta(days=1)
    else:
        complete = False
    assert (
        price_usage(policy, "fixture-model", model, date.today(), values, complete=complete)[0]
        is None
    )


def test_runtime_persists_priced_receipt_and_settles_exactly_once(assistant):
    assistant.store.policy.text_pricing = pricing()
    assistant.store.policy.billing_project = "farmable-test"
    script(
        assistant,
        [[wire([{"text": "Hello"}], usageMetadata=usage(), modelVersion="fixture-version")]],
    )
    assert post(assistant)[0].status_code == 200
    with assistant.sessions() as session:
        call = session.scalar(select(AssistantModelCall))
        assert call.state == "priced" and call.estimated_micro_usd == 112
        assert call.data_kind == "synthetic" and call.billing_project == "farmable-test"
        assert session.get(AssistantBudget, 1).reserved_micro_usd == 112
        cost = session.get(AssistantTurnCost, call.cost_id)
        assert cost.state == "settled" and cost.settled_micro_usd == 112
        assert cost.error == "reservation_exceeded"
        call_id = call.id
        cost_id = cost.id
    accounting.reconcile_cost(assistant.sessions, cost_id)
    accounting.finish_call(assistant.sessions, call_id, {}, None, complete=False)
    with assistant.sessions() as session:
        assert session.get(AssistantModelCall, call_id).estimated_micro_usd == 112
        assert session.get(AssistantBudget, 1).reserved_micro_usd == 112


@pytest.mark.parametrize("outcome", ["refund", "unknown", "overrun", "prior_day", "erased"])
def test_settlement_handles_terminal_costs_without_releasing_unknown_spend(assistant, outcome):
    assistant.store.policy.text_pricing = pricing()
    assistant.store.policy.turn_reserve_micro_usd = 500 if outcome == "refund" else 10
    assistant.store.policy.daily_budget_micro_usd = 100 if outcome == "overrun" else 1000
    identifier = uuid4()
    assistant.store.admit(
        assistant.alice.auth, assistant.conversation, TurnCreate(id=identifier, message="Test")
    )
    receipt = accounting.begin_call(
        assistant.store, assistant.alice.auth, assistant.conversation, identifier, 0
    )
    accounting.reconcile_turn(assistant.sessions, identifier)
    with assistant.sessions() as session:
        cost_id = session.get(AssistantModelCall, receipt).cost_id
        assert session.get(AssistantTurnCost, cost_id).state == "reserved"
    assistant.store.interrupt(assistant.alice.auth, assistant.conversation, identifier)
    if outcome == "erased":
        from farmable_backend.models import User

        with assistant.sessions.begin() as session:
            session.delete(session.get(User, assistant.alice.owner))
    if outcome == "prior_day":
        with assistant.sessions.begin() as session:
            session.get(AssistantTurnCost, cost_id).day -= timedelta(days=1)
    if outcome != "unknown":
        accounting.finish_call(
            assistant.sessions, receipt, usage(), "fixture-version", complete=True
        )
    for _ in range(2):
        accounting.reconcile_cost(assistant.sessions, cost_id)
    with assistant.sessions() as session:
        cost = session.get(AssistantTurnCost, cost_id)
        assert cost.state == ("unknown" if outcome == "unknown" else "settled")
        assert session.get(AssistantBudget, 1).reserved_micro_usd == (
            10 if outcome in {"unknown", "prior_day"} else 112
        )
    if outcome == "overrun":
        with pytest.raises(ApiError, match="assistant_budget_exhausted"):
            assistant.store.admit(
                assistant.alice.auth,
                assistant.conversation,
                TurnCreate(id=uuid4(), message="Again"),
            )


def test_worker_settles_abandoned_turn_without_any_provider_calls(assistant):
    from farmable_backend.models import AssistantTurn

    identifier = uuid4()
    assistant.store.admit(
        assistant.alice.auth, assistant.conversation, TurnCreate(id=identifier, message="Test")
    )
    with assistant.sessions.begin() as session:
        session.get(AssistantTurn, identifier).deadline = datetime.now(UTC) - timedelta(seconds=1)
    assert accounting.reconcile_batch(assistant.sessions) == 1
    with assistant.sessions() as session:
        assert session.get(AssistantTurn, identifier).status == "failed"
        assert session.get(AssistantBudget, 1).reserved_micro_usd == 0


def test_cancel_and_account_deletion_preserve_only_content_free_receipt(assistant):
    assistant.store.policy.text_pricing = pricing()
    identifier = uuid4()
    assistant.store.admit(
        assistant.alice.auth, assistant.conversation, TurnCreate(id=identifier, message="private")
    )
    receipt = accounting.begin_call(
        assistant.store, assistant.alice.auth, assistant.conversation, identifier, 0
    )
    with pytest.raises(ApiError, match="assistant_call_already_started"):
        accounting.begin_call(
            assistant.store, assistant.alice.auth, assistant.conversation, identifier, 0
        )
    assistant.store.interrupt(assistant.alice.auth, assistant.conversation, identifier)
    accounting.finish_call(assistant.sessions, receipt, usage(), "fixture-version", complete=False)
    exported = AccountService(assistant.sessions).export_document(assistant.alice.auth)
    assert exported["assistant_model_calls"][0]["state"] == "unknown"
    with assistant.sessions.begin() as session:
        session.get(AuthIdentity, assistant.alice.owner).password_hash = PASSWORD_HASHER.hash(
            "fixture password"
        )
    AccountService(assistant.sessions).delete_account(assistant.alice.auth, "fixture password")
    accounting.finish_call(assistant.sessions, receipt, usage(), "fixture-version", complete=True)
    with assistant.sessions() as session:
        call = session.get(AssistantModelCall, receipt)
        assert call.turn_id is None and call.estimated_micro_usd is None
        assert call.state == "unknown" and call.usage == usage()


def test_runtime_failure_keeps_partial_numbers_without_claiming_settlement(assistant):
    script(
        assistant,
        [
            [
                wire([{"text": "Partial"}], finish=None, usageMetadata=usage()),
                ApiError(503, "assistant_unavailable"),
            ]
        ],
    )
    _, events, _ = post(assistant)
    assert events[-1]["type"] == "error"
    with assistant.sessions() as session:
        call = session.scalar(select(AssistantModelCall))
        assert call.state == "unknown" and call.usage == usage()
        assert call.estimated_micro_usd is None


def test_stale_or_missing_usage_is_visible_to_reconciliation(assistant):
    first = datetime.now(UTC) - timedelta(days=1)
    last = first + timedelta(days=2)
    with assistant.sessions.begin() as session:
        cost = AssistantTurnCost(
            day=date.today(),
            policy="synthetic",
            reserved_micro_usd=10,
            state="reserved",
            next_check_at=datetime.now(UTC),
        )
        session.add(cost)
        session.flush()
        session.add(
            AssistantModelCall(
                cost_id=cost.id,
                round_index=0,
                model="test-model",
                data_kind="provider",
                state="started",
                usage={},
                billing_project="farmable-test",
                created_at=datetime.now(UTC),
            )
        )
    totals = ledger_totals(assistant.sessions, "farmable-test", first, last)
    assert totals["unknown_calls"] == 1 and totals["estimated_micro_usd"] == 0
    assert compare({"gross_usd": "0"}, totals)["status"] == "incomplete_ledger"


def billing_row():
    return {
        "billing_account_id": "fixture-account",
        "project": {"id": "farmable-test"},
        "service": {"id": "fixture-service"},
        "currency": "USD",
        "cost": "0.001",
        "credits": [{"amount": "-0.0001"}],
        "cost_type": "regular",
        "invoice": {"month": "202609"},
        "usage_start_time": "2026-09-01T00:00:00Z",
        "usage_end_time": "2026-09-01T01:00:00Z",
        "export_time": "2026-09-02T00:00:00Z",
    }


def imported(documents):
    return export_totals(
        json.dumps(documents).encode(),
        account="fixture-account",
        project="farmable-test",
        service_ids=["fixture-service"],
        start=datetime(2026, 9, 1, tzinfo=UTC),
        end=datetime(2026, 9, 2, tzinfo=UTC),
    )


def test_export_is_project_scoped_preserves_credits_and_is_snapshot_idempotent():
    other = copy.deepcopy(billing_row())
    other["project"]["id"] = "invoice-other"
    other["cost"] = "999999"
    result = imported([billing_row(), other])
    assert result == imported([billing_row(), other])
    assert result["gross_usd"] == "0.001" and result["net_usd"] == "0.0009"
    assert result["selected_rows"] == 1 and result["ignored_rows"] == 1
    assert "fixture-account" not in json.dumps(result)


@pytest.mark.parametrize(
    "field,value",
    [
        ("currency", "ZAR"),
        ("cost", "NaN"),
        ("cost", True),
        ("usage_start_time", "2026-08-31T23:00:00Z"),
        ("usage_end_time", "2026-09-01T01:00:00"),
        ("credits", None),
        ("invoice", {"month": "202613"}),
    ],
)
def test_ambiguous_billing_inputs_fail_closed(field, value):
    row = billing_row()
    row[field] = value
    with pytest.raises(ReconciliationError):
        imported([row])


def test_migration_matches_content_free_receipts():
    output = io.StringIO()
    command.upgrade(Config("alembic.ini", output_buffer=output), "0015:0016", sql=True)
    sql = output.getvalue()
    assert "ON DELETE SET NULL" in sql and "INSERT INTO" not in sql
    for name in ("assistant_model_calls", "assistant_turn_costs"):
        assert _table_elements(sql, name) == _table_elements(_orm_sql(name), name)
        assert _index_statements(sql, name) == _index_statements(_orm_sql(name), name)
