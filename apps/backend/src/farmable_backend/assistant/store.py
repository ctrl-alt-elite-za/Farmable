"""Short ORM transactions. Never hold database locks across provider I/O."""

from datetime import timedelta

from sqlalchemy import func, select, tuple_, update
from sqlalchemy.exc import IntegrityError

from farmable_backend.assistant.privacy import NOTICE_VERSION, ConsentView
from farmable_backend.assistant.retention import erase_if_due, visible
from farmable_backend.assistant.schemas import ConversationView, History, TurnView
from farmable_backend.models import (
    AssistantBudget,
    AssistantConsent,
    AssistantConversation,
    AssistantTurn,
)
from farmable_backend.record_access import ApiError, authenticate, db_now, farm_scope, utc


def view(turn):
    return TurnView(
        id=turn.id,
        conversation_id=turn.conversation_id,
        status=turn.status,
        message=turn.message,
        reply=turn.reply,
        tools=turn.tools,
        error=turn.error,
        created_at=utc(turn.created_at),
        deadline=utc(turn.deadline),
        content_deleted_at=utc(turn.content_deleted_at) if turn.content_deleted_at else None,
        reserved_micro_usd=turn.reserved_micro_usd,
        usage=turn.usage,
    )


class Store:
    def __init__(self, sessions, policy, services):
        self.sessions, self.policy, self.services = sessions, policy, services

    def model(self):
        return (
            "fixture-model"
            if self.services.integrations_mode == "fake"
            else self.services.gemini_model or ""
        )

    def consent_valid(self, record):
        return bool(
            record is not None
            and record.withdrawn_at is None
            and record.notice_version == NOTICE_VERSION
            and record.model == self.model()
            and record.model
        )

    def require_consent(self, session, conversation_id):
        if not self.consent_valid(session.get(AssistantConsent, conversation_id)):
            raise ApiError(403, "assistant_consent_required")

    def consent(self, auth, conversation_id, payload=None, *, withdraw=False):
        with self.sessions.begin() as session:
            conversation = self.scope(session, auth, conversation_id, lock=True)
            record = session.get(AssistantConsent, conversation_id)
            if withdraw:
                if record is not None and record.withdrawn_at is None:
                    record.withdrawn_at = db_now(session)
                # Always fence running turns, including legacy/unconsented ones.
                self.cancel_conversation(session, conversation_id)
            elif payload is not None:
                if not self.model() or payload.model != self.model():
                    raise ApiError(409, "assistant_consent_model_changed")
                if payload.notice_version != NOTICE_VERSION:
                    raise ApiError(409, "assistant_consent_notice_changed")
                if not self.consent_valid(record):
                    # A regrant must not revive a turn admitted under old consent.
                    self.cancel_conversation(session, conversation_id)
                    if record is None:
                        record = AssistantConsent(
                            id=conversation.id, owner_id=conversation.owner_id
                        )
                        session.add(record)
                    record.model, record.notice_version = self.model(), NOTICE_VERSION
                    record.granted_at, record.withdrawn_at = db_now(session), None
            return ConsentView(
                model=self.model(),
                granted=self.consent_valid(record),
                granted_at=utc(record.granted_at) if record is not None else None,
                withdrawn_at=(
                    utc(record.withdrawn_at)
                    if record is not None and record.withdrawn_at is not None
                    else None
                ),
            )

    @staticmethod
    def cancel_conversation(session, conversation_id):
        session.execute(
            update(AssistantTurn)
            .where(
                AssistantTurn.conversation_id == conversation_id,
                AssistantTurn.status == "running",
            )
            .values(status="interrupted", error="assistant_consent_withdrawn")
        )

    def scope(self, session, auth, conversation_id, *, lock=False):
        owner = authenticate(session, auth)
        initial = session.get(AssistantConversation, conversation_id)
        if initial is None or initial.owner_id != owner:
            raise ApiError(404, "not_found")
        farm_scope(session, owner, initial.farm_id, lock=lock)
        if lock:
            initial = session.scalar(
                select(AssistantConversation)
                .where(AssistantConversation.id == conversation_id)
                .with_for_update()
                .execution_options(populate_existing=True)
            )
            if initial is None:
                raise ApiError(404, "not_found")
        return initial

    def create(self, auth, payload):
        try:
            with self.sessions.begin() as session:
                owner = authenticate(session, auth)
                farm_scope(session, owner, payload.farm_id, lock=True)
                record = session.get(AssistantConversation, payload.id)
                if record is not None:
                    if record.owner_id != owner or record.farm_id != payload.farm_id:
                        raise ApiError(409, "conversation_conflict")
                else:
                    count = session.scalar(
                        select(func.count())
                        .select_from(AssistantConversation)
                        .where(AssistantConversation.farm_id == payload.farm_id)
                    )
                    if count >= 100:
                        raise ApiError(429, "conversation_limit", 86400)
                    record = AssistantConversation(
                        id=payload.id, owner_id=owner, farm_id=payload.farm_id
                    )
                    session.add(record)
                    session.flush()
                return ConversationView(
                    id=record.id, farm_id=record.farm_id, created_at=utc(record.created_at)
                )
        except IntegrityError:
            raise ApiError(409, "conversation_conflict") from None

    def expire(self, session, record):
        if erase_if_due(record, db_now(session)):
            return
        if record.status == "running" and utc(record.deadline) <= db_now(session):
            record.status, record.error = "failed", "turn_expired"
        if record.status == "running" and (
            record.model != self.model()
            or not self.consent_valid(session.get(AssistantConsent, record.conversation_id))
        ):
            record.status, record.error = "interrupted", "assistant_consent_required"

    def admit(self, auth, conversation_id, payload):
        try:
            with self.sessions.begin() as session:
                # Seeded by the migration: no racy get-or-insert on first use.
                owner = authenticate(session, auth)
                budget = session.scalar(
                    select(AssistantBudget).where(AssistantBudget.id == 1).with_for_update()
                )
                if budget is None:
                    raise ApiError(503, "assistant_migration_required")
                conversation = self.scope(session, auth, conversation_id, lock=True)
                existing = self.locked_turn(session, payload.id)
                if existing is not None:
                    if existing.conversation_id != conversation_id or existing.owner_id != owner:
                        raise ApiError(409, "turn_conflict")
                    self.expire(session, existing)
                    if existing.content_deleted_at is None and existing.message != payload.message:
                        raise ApiError(409, "turn_conflict")
                    return view(existing), False
                now = db_now(session)
                model = self.model()
                if not self.policy.enabled or self.services.integrations_mode == "disabled":
                    raise ApiError(503, "assistant_disabled")
                if self.services.integrations_mode == "live" and not self.services.gemini_api_key:
                    raise ApiError(503, "assistant_unconfigured")
                self.policy.validate_live(now.date(), model)
                self.require_consent(session, conversation_id)
                policy_hash = self.policy.fingerprint()
                if budget.day != now.date():
                    budget.day, budget.policy, budget.reserved_micro_usd = (
                        now.date(),
                        policy_hash,
                        0,
                    )
                elif budget.policy != policy_hash:
                    # Mixed replica policies must not increase the limit mid-day.
                    raise ApiError(503, "assistant_policy_mismatch")
                recent = list(
                    session.scalars(
                        select(AssistantTurn)
                        .where(
                            AssistantTurn.owner_id == owner,
                            AssistantTurn.created_at >= now - timedelta(days=1),
                        )
                        .order_by(AssistantTurn.created_at)
                        .limit(101)
                    )
                )
                for turn in recent:
                    self.expire(session, turn)
                if any(turn.status == "running" for turn in recent):
                    raise ApiError(409, "turn_in_progress")
                if len(recent) >= self.policy.daily_turns_per_user:
                    raise ApiError(429, "assistant_daily_limit", 86400)
                if sum(utc(t.created_at) > now - timedelta(minutes=1) for t in recent) >= 3:
                    raise ApiError(429, "assistant_rate_limited", 60)
                reserve = self.policy.turn_reserve_micro_usd
                if budget.reserved_micro_usd + reserve > self.policy.daily_budget_micro_usd:
                    raise ApiError(429, "assistant_budget_exhausted", 86400)
                budget.reserved_micro_usd += reserve
                record = AssistantTurn(
                    id=payload.id,
                    conversation_id=conversation.id,
                    owner_id=owner,
                    message=payload.message,
                    reply="",
                    tools=[],
                    usage=[],
                    status="running",
                    deadline=now + timedelta(seconds=90),
                    created_at=now,
                    model=model,
                    policy=policy_hash,
                    reserved_micro_usd=reserve,
                )
                session.add(record)
                session.flush()
                return view(record), True
        except IntegrityError:
            raise ApiError(409, "turn_conflict") from None

    def get(self, auth, conversation_id, turn_id):
        with self.sessions.begin() as session:
            self.scope(session, auth, conversation_id, lock=True)
            record = self.locked_turn(session, turn_id)
            if record is None or record.conversation_id != conversation_id:
                raise ApiError(404, "not_found")
            self.expire(session, record)
            return view(record)

    def history(self, auth, conversation_id, before=None):
        with self.sessions.begin() as session:
            self.scope(session, auth, conversation_id, lock=True)
            query = select(AssistantTurn).where(
                AssistantTurn.conversation_id == conversation_id, *visible(db_now(session))
            )
            if before is not None:
                cursor = session.get(AssistantTurn, before)
                if cursor is None or cursor.conversation_id != conversation_id:
                    raise ApiError(404, "not_found")
                query = query.where(
                    tuple_(AssistantTurn.created_at, AssistantTurn.id)
                    < (cursor.created_at, cursor.id)
                )
            records = list(
                session.scalars(
                    query.order_by(AssistantTurn.created_at.desc(), AssistantTurn.id.desc()).limit(
                        21
                    )
                )
            )
            for record in records[:20]:
                self.expire(session, record)
            return History(
                turns=[view(t) for t in records[:20]],
                next_before=records[19].id if len(records) > 20 else None,
            )

    def update(
        self,
        auth,
        conversation_id,
        turn_id,
        *,
        reply=None,
        tools=None,
        usage=None,
        status=None,
        error=None,
    ):
        with self.sessions.begin() as session:
            self.scope(session, auth, conversation_id, lock=True)
            record = self.locked_turn(session, turn_id)
            if record is None or record.conversation_id != conversation_id:
                raise ApiError(404, "not_found")
            self.expire(session, record)
            # Cancellation wins over late provider callbacks and process restarts.
            if record.status == "running" and record.content_deleted_at is None:
                if reply is not None:
                    record.reply = reply
                if tools is not None:
                    record.tools = tools
                if usage is not None:
                    record.usage = usage
                if status is not None:
                    record.status, record.error = status, error
            return view(record)

    def interrupt(self, auth, conversation_id, turn_id):
        return self.update(auth, conversation_id, turn_id, status="interrupted")

    @staticmethod
    def locked_turn(session, turn_id):
        # The purger takes only turn locks. Reload after obtaining the same lock,
        # so a late provider callback cannot restore erased content from an ORM snapshot.
        return session.scalar(
            select(AssistantTurn)
            .where(AssistantTurn.id == turn_id)
            .with_for_update()
            .execution_options(populate_existing=True)
        )
