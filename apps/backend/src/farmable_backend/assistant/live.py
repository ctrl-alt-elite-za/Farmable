"""Consent and read capabilities for direct-to-Gemini audio. No server audio proxy."""

import json
from datetime import datetime, timedelta
from typing import Any, Literal
from uuid import UUID

from pydantic import Field, model_validator
from sqlalchemy import select, update
from sqlalchemy.exc import IntegrityError

from farmable_backend.assistant.runtime import SYSTEM
from farmable_backend.assistant.tools import DECLARATIONS, execute
from farmable_backend.models import AssistantLiveConsent, AssistantLiveSession, User
from farmable_backend.record_access import ApiError, db_now, utc
from farmable_backend.schemas import StrictModel
from farmable_backend.voice_api import LiveSessionResponse, consume_attempt

LIVE_NOTICE_VERSION = "gemini-live-conversation-v1"
LIVE_NOTICE = (
    "Allow microphone audio, typed input and requested farm/planning data (including budget) "
    "to be sent to Google Gemini Live for spoken answers. Farmable's backend does not receive "
    "or store the direct audio or provider transcripts. Voice-session metadata and this consent "
    "receipt remain until account deletion. Text-chat history has its separate 30-day policy. "
    "Google retention depends on the operator's account terms. Withdrawing stops new credentials "
    "and farm-tool access, but cannot revoke an already-issued direct connection: the app must "
    "stop recording/playback and disconnect. The credential expires after at most ten minutes "
    "from issuance. Withdrawal cannot recall data already sent. Saved plans require a separate "
    "explicit confirmation; saying yes to the voice model cannot save a plan."
)


class LiveConsentGrant(StrictModel):
    notice_version: Literal["gemini-live-conversation-v1"]
    model: str = Field(min_length=1, max_length=128)


class LiveConsentView(StrictModel):
    notice_version: str = LIVE_NOTICE_VERSION
    notice: str = LIVE_NOTICE
    model: str
    granted: bool
    granted_at: datetime | None
    withdrawn_at: datetime | None


class LiveStart(StrictModel):
    id: UUID


class LiveState(StrictModel):
    id: UUID
    state: Literal["issuing", "active", "interrupted", "failed", "expired"]
    expires_at: datetime
    tool_count: int
    disconnect_required: bool


class LiveIssued(LiveSessionResponse):
    id: UUID
    lease_expires_at: datetime
    setup: dict[str, Any]


class LiveToolCall(StrictModel):
    id: str = Field(min_length=1, max_length=128)
    name: Literal["list_sections", "get_crop_outlook", "preview_planting_plan"]
    args: dict[str, Any]

    @model_validator(mode="after")
    def bounded(self):
        if len(json.dumps(self.args).encode()) > 4096:
            raise ValueError("Tool arguments exceed the limit")
        return self


class LiveToolResult(StrictModel):
    id: str
    name: str
    response: dict[str, Any]


def setup_for(model):
    return {
        "model": "models/" + model,
        "generationConfig": {"responseModalities": ["AUDIO"], "maxOutputTokens": 1024},
        "systemInstruction": {
            "parts": [
                {
                    "text": SYSTEM
                    + (
                        "\nYou are speaking in a Gemini Live session. "
                        "Use the read tools for farm facts. Never claim a plan has been saved. "
                        "Ask the farmer to review and confirm it in the app. "
                        "Ask for clarification when speech or language is unclear; "
                        "do not invent a translation."
                    )
                }
            ]
        },
        "tools": [{"functionDeclarations": DECLARATIONS}],
        "inputAudioTranscription": {},
        "outputAudioTranscription": {},
        "realtimeInputConfig": {"activityHandling": "START_OF_ACTIVITY_INTERRUPTS"},
        "sessionResumption": {},
    }


class LiveStore:
    def __init__(self, store, adapter):
        self.store, self.sessions, self.services = store, store.sessions, store.services
        self.scope = store.scope
        self.adapter = adapter

    @property
    def configured(self):
        return self.adapter.configured

    def model(self):
        return self.services.gemini_live_model or ""

    def valid(self, record):
        return bool(
            record
            and record.withdrawn_at is None
            and record.notice_version == LIVE_NOTICE_VERSION
            and record.model == self.model()
            and record.model
        )

    def require_consent(self, session, conversation_id):
        if not self.valid(session.get(AssistantLiveConsent, conversation_id)):
            raise ApiError(403, "voice_consent_required")

    def consent(self, auth, conversation_id, payload=None, withdraw=False):
        with self.sessions.begin() as session:
            conversation = self.scope(session, auth, conversation_id, lock=True)
            record = session.get(AssistantLiveConsent, conversation_id)
            if withdraw or (payload is not None and not self.valid(record)):
                session.execute(
                    update(AssistantLiveSession)
                    .where(
                        AssistantLiveSession.conversation_id == conversation_id,
                        AssistantLiveSession.state.in_(("issuing", "active")),
                    )
                    .values(state="interrupted")
                )
            if withdraw:
                if record is not None and record.withdrawn_at is None:
                    record.withdrawn_at = db_now(session)
            elif payload is not None:
                if not self.model() or payload.model != self.model():
                    raise ApiError(409, "voice_consent_model_changed")
                if payload.notice_version != LIVE_NOTICE_VERSION:
                    raise ApiError(409, "voice_consent_notice_changed")
                if not self.valid(record):
                    if record is None:
                        record = AssistantLiveConsent(
                            id=conversation_id, owner_id=conversation.owner_id
                        )
                        session.add(record)
                    record.model, record.notice_version = self.model(), LIVE_NOTICE_VERSION
                    record.granted_at, record.withdrawn_at = db_now(session), None
            return LiveConsentView(
                model=self.model(),
                granted=self.valid(record),
                granted_at=utc(record.granted_at) if record else None,
                withdrawn_at=utc(record.withdrawn_at) if record and record.withdrawn_at else None,
            )

    def admit(self, auth, conversation_id, identifier):
        try:
            with self.sessions.begin() as session:
                conversation = self.scope(session, auth, conversation_id, lock=True)
                self.require_consent(session, conversation_id)
                if not self.configured:
                    raise ApiError(503, "voice_disabled")
                owner = conversation.owner_id
                session.scalar(select(User).where(User.id == owner).with_for_update())
                if session.get(AssistantLiveSession, identifier) is not None:
                    raise ApiError(409, "voice_session_not_replayable")
                now = db_now(session)
                active = session.scalar(
                    select(AssistantLiveSession.id)
                    .where(
                        AssistantLiveSession.owner_id == owner,
                        AssistantLiveSession.state.in_(("issuing", "active")),
                        AssistantLiveSession.expires_at > now,
                    )
                    .limit(1)
                )
                if active is not None:
                    raise ApiError(409, "voice_session_in_progress")
                consume_attempt(session, owner)
                record = AssistantLiveSession(
                    id=identifier,
                    conversation_id=conversation_id,
                    owner_id=owner,
                    model=self.model(),
                    expires_at=now + timedelta(minutes=10),
                )
                session.add(record)
                session.flush()
                return record.model
        except IntegrityError:
            raise ApiError(409, "voice_session_not_replayable") from None

    def owned(self, session, auth, conversation_id, identifier):
        self.scope(session, auth, conversation_id, lock=True)
        record = session.get(AssistantLiveSession, identifier, with_for_update=True)
        if record is None or record.conversation_id != conversation_id:
            raise ApiError(404, "not_found")
        return record

    def require_active(self, session, record, *, issuing=False):
        self.require_consent(session, record.conversation_id)
        if not self.configured or record.model != self.model():
            raise ApiError(409, "voice_configuration_changed")
        if utc(record.expires_at) <= db_now(session):
            raise ApiError(409, "voice_session_expired")
        if record.state != ("issuing" if issuing else "active"):
            raise ApiError(409, "voice_session_ended")

    def activate(self, auth, conversation_id, identifier, issued_model):
        with self.sessions.begin() as session:
            record = self.owned(session, auth, conversation_id, identifier)
            self.require_active(session, record, issuing=True)
            if issued_model != "models/" + record.model:
                raise ApiError(409, "voice_configuration_changed")
            record.state = "active"
            return utc(record.expires_at)

    def fail(self, identifier):
        with self.sessions.begin() as session:
            session.execute(
                update(AssistantLiveSession)
                .where(
                    AssistantLiveSession.id == identifier,
                    AssistantLiveSession.state == "issuing",
                )
                .values(state="failed")
            )

    def state(self, auth, conversation_id, identifier, interrupt=False):
        with self.sessions.begin() as session:
            record = self.owned(session, auth, conversation_id, identifier)
            if interrupt and record.state in ("issuing", "active"):
                record.state = "interrupted"
            state = "expired" if utc(record.expires_at) <= db_now(session) else record.state
            allowed = (
                state == "active"
                and self.configured
                and record.model == self.model()
                and self.valid(session.get(AssistantLiveConsent, conversation_id))
            )
            return LiveState(
                id=record.id,
                state=state,
                expires_at=utc(record.expires_at),
                tool_count=record.tool_count,
                disconnect_required=not allowed,
            )

    def check_tool(self, auth, conversation_id, identifier, consume=False):
        with self.sessions.begin() as session:
            record = self.owned(session, auth, conversation_id, identifier)
            self.require_active(session, record)
            if consume:
                if record.tool_count >= 32:
                    raise ApiError(429, "voice_tool_limit")
                record.tool_count += 1

    def tool(self, auth, conversation_id, identifier, payload, mode):
        # Reserve the attempt before executing a read, with no locks across the
        # separate tool transaction. Recheck before returning any farm content.
        self.check_tool(auth, conversation_id, identifier, consume=True)
        result = execute(self, auth, conversation_id, payload.name, payload.args, mode)
        self.check_tool(auth, conversation_id, identifier)
        return LiveToolResult(id=payload.id, name=payload.name, response=result)
