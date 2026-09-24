"""Durable usage receipts and idempotent reservation settlement; no invoice claims."""

import asyncio
import logging
import re
from datetime import timedelta

from sqlalchemy import select

from farmable_backend.assistant.pricing import TextPricePolicy, price_usage
from farmable_backend.models import (
    AssistantBudget,
    AssistantModelCall,
    AssistantTurn,
    AssistantTurnCost,
)
from farmable_backend.record_access import ApiError, db_now, utc


def begin_call(store, auth, conversation_id, turn_id, round_index):
    if type(round_index) is not int or not 0 <= round_index < 4:
        raise ApiError(502, "assistant_call_limit")
    with store.sessions.begin() as session:
        store.scope(session, auth, conversation_id, lock=True)
        turn = store.locked_turn(session, turn_id)
        if turn is None or turn.conversation_id != conversation_id:
            raise ApiError(404, "not_found")
        store.expire(session, turn)
        if turn.status != "running":
            raise ApiError(409, "assistant_call_cancelled")
        existing = session.scalar(
            select(AssistantModelCall.id).where(
                AssistantModelCall.turn_id == turn_id,
                AssistantModelCall.round_index == round_index,
            )
        )
        if existing is not None:
            # A process restart must not replay an ambiguously billed exchange.
            raise ApiError(409, "assistant_call_already_started")
        pricing = store.policy.text_pricing
        cost = session.scalar(
            select(AssistantTurnCost)
            .where(
                AssistantTurnCost.turn_id == turn_id,
            )
            .with_for_update()
        )
        if cost is None or cost.state == "settled":
            raise ApiError(503, "assistant_accounting_required")
        row = AssistantModelCall(
            cost_id=cost.id,
            turn_id=turn_id,
            round_index=round_index,
            model=turn.model,
            billing_project=store.policy.billing_project,
            pricing=pricing.model_dump(mode="json") if pricing else None,
            data_kind="synthetic" if store.services.integrations_mode == "fake" else "provider",
            state="started",
            usage={},
            created_at=db_now(session),
        )
        session.add(row)
        session.flush()
        return row.id


def note_cache(sessions, identifier, mode, cost):
    with sessions.begin() as session:
        row = session.get(AssistantModelCall, identifier, with_for_update=True)
        if row is None or row.state != "started":
            raise ApiError(409, "assistant_call_cancelled")
        row.cache_mode, row.cache_cost_micro_usd = mode, cost


def finish_call(sessions, identifier, usage, response_model, *, complete):
    # Internal worker callback only. It can retain numeric usage after cancellation
    # or erasure, but cannot restore chat, ownership links or consent.
    with sessions.begin() as session:
        row = session.scalar(
            select(AssistantModelCall)
            .where(
                AssistantModelCall.id == identifier,
            )
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if row is None or row.state != "started":
            return
        allowed = {
            "promptTokenCount",
            "candidatesTokenCount",
            "thoughtsTokenCount",
            "totalTokenCount",
            "cachedContentTokenCount",
        }
        valid = (
            isinstance(usage, dict)
            and usage.keys() <= allowed
            and all(type(value) is int and 0 <= value <= 10_000_000 for value in usage.values())
        )
        row.usage = dict(usage) if valid else {}
        row.response_model = (
            response_model
            if isinstance(response_model, str)
            and re.fullmatch(
                r"[a-zA-Z0-9._-]{1,128}",
                response_model,
            )
            else None
        )
        policy = TextPricePolicy.model_validate(row.pricing) if row.pricing else None
        cost, error = price_usage(
            policy,
            row.model,
            row.response_model,
            utc(row.created_at).date(),
            row.usage,
            complete=complete and valid,
        )
        if row.cache_cost_micro_usd is None:
            cost, error = None, "cache_cost_unknown"
        elif cost is not None:
            cost += row.cache_cost_micro_usd
        row.state = (
            "priced" if cost is not None else ("unpriced" if complete and valid else "unknown")
        )
        row.estimated_micro_usd, row.error = cost, error
        row.finished_at = db_now(session)


def reconcile_cost(sessions, identifier):
    with sessions.begin() as session:
        # Same global-first lock order as admission. No provider/network I/O here.
        budget = session.get(AssistantBudget, 1, with_for_update=True)
        initial = session.get(AssistantTurnCost, identifier)
        if initial is None or budget is None:
            return
        turn = (
            session.get(AssistantTurn, initial.turn_id, with_for_update=True)
            if initial.turn_id
            else None
        )
        cost = session.scalar(
            select(AssistantTurnCost)
            .where(
                AssistantTurnCost.id == identifier,
            )
            .with_for_update()
            .execution_options(populate_existing=True)
        )
        if cost.state == "settled":
            return
        now = db_now(session)
        cost.next_check_at = now + timedelta(seconds=60)
        if turn is not None and turn.status == "running":
            if utc(turn.deadline) > now:
                return
            turn.status, turn.error = "failed", "turn_expired"
        calls = session.scalars(
            select(AssistantModelCall)
            .where(
                AssistantModelCall.cost_id == cost.id,
            )
            .order_by(AssistantModelCall.id)
            .with_for_update()
        ).all()
        if any(call.state != "priced" or call.estimated_micro_usd is None for call in calls):
            cost.state, cost.error = "unknown", "usage_unsettled"
            return
        total = sum(call.estimated_micro_usd for call in calls)
        if budget.day == cost.day:
            if budget.policy != cost.policy or budget.reserved_micro_usd < cost.reserved_micro_usd:
                cost.state, cost.error = "unknown", "budget_reconciliation_mismatch"
                return
            # This counter is the day's held reservations + settled costs. Never
            # clamp an overrun away or increase the configured admission limit.
            budget.reserved_micro_usd += total - cost.reserved_micro_usd
        # A late prior-day settlement cannot refund today's budget.
        cost.state, cost.settled_micro_usd, cost.settled_at = "settled", total, now
        cost.error = "reservation_exceeded" if total > cost.reserved_micro_usd else None


def reconcile_turn(sessions, turn_id):
    with sessions() as session:
        identifier = session.scalar(
            select(AssistantTurnCost.id).where(AssistantTurnCost.turn_id == turn_id)
        )
    if identifier is not None:
        reconcile_cost(sessions, identifier)


def reconcile_batch(sessions):
    with sessions() as session:
        identifiers = session.scalars(
            select(AssistantTurnCost.id)
            .where(
                AssistantTurnCost.state != "settled",
                AssistantTurnCost.next_check_at <= db_now(session),
            )
            .order_by(AssistantTurnCost.next_check_at, AssistantTurnCost.id)
            .limit(100)
        ).all()
    for identifier in identifiers:
        reconcile_cost(sessions, identifier)
    return len(identifiers)


class AccountingWorker:
    def __init__(self, sessions):
        self.sessions = sessions
        self.stop = asyncio.Event()

    async def run(self):
        while not self.stop.is_set():
            try:
                count = await asyncio.to_thread(reconcile_batch, self.sessions)
            except Exception:
                logging.getLogger(__name__).error("Assistant accounting reconciliation unavailable")
                count = 0
            try:
                await asyncio.wait_for(self.stop.wait(), 1 if count == 100 else 60)
            except TimeoutError:
                pass
