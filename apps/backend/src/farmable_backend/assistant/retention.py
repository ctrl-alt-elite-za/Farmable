"""Fixed-age chat-content retention; billing/idempotency metadata is not refunded."""

import asyncio
import logging
from datetime import timedelta

from sqlalchemy import select

from farmable_backend.models import AssistantTurn
from farmable_backend.record_access import db_now, utc

RETENTION_DAYS = 30
BATCH_SIZE = 100
logger = logging.getLogger(__name__)


def cutoff(now):
    return now - timedelta(days=RETENTION_DAYS)


def visible(now):
    return (
        AssistantTurn.created_at > cutoff(now),
        AssistantTurn.content_deleted_at.is_(None),
    )


def erase_if_due(record, now):
    if record.content_deleted_at is not None:
        return True
    if utc(record.created_at) > cutoff(now):
        return False
    record.message, record.reply, record.tools = "", "", []
    record.content_deleted_at = now
    if record.status == "running":
        record.status, record.error = "failed", "assistant_history_expired"
    return True


def purge_batch(sessions):
    with sessions.begin() as session:
        now = db_now(session)
        records = list(
            session.scalars(
                select(AssistantTurn)
                .where(
                    AssistantTurn.created_at <= cutoff(now),
                    AssistantTurn.content_deleted_at.is_(None),
                )
                .order_by(AssistantTurn.created_at, AssistantTurn.id)
                .limit(BATCH_SIZE)
                .with_for_update(skip_locked=True)
            )
        )
        for record in records:
            erase_if_due(record, now)
        return len(records)


class RetentionWorker:
    def __init__(self, sessions):
        self.sessions = sessions
        self.stop = asyncio.Event()

    async def run(self):
        while not self.stop.is_set():
            try:
                count = await asyncio.to_thread(purge_batch, self.sessions)
            except Exception:
                # Never log messages, tool output, credentials or database exceptions.
                logger.error("Assistant retention cleanup unavailable")
                count = 0
            try:
                await asyncio.wait_for(self.stop.wait(), timeout=1 if count == BATCH_SIZE else 60)
            except TimeoutError:
                pass
