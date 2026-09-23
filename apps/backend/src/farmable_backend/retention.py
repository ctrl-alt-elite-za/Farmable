"""Bounded, repeatable cleanup for authentication and privacy artifacts."""

from datetime import UTC, datetime, timedelta

from sqlalchemy import delete

from farmable_backend.models import (
    AuthSession,
    ExportJob,
    IdempotencyRecord,
    RateLimitCounter,
    VerificationChallenge,
)


def cleanup(sessions, *, now: datetime | None = None, batch_size: int = 500) -> dict[str, int]:
    """Delete expired/old security records in bounded batches.

    Every predicate is time based and the operation is safe to retry. Export
    cleanup also clears large artifacts through the account service's
    state-transition path before deleting already-expired rows here.
    """
    current = now or datetime.now(UTC)
    cutoffs = {
        "sessions": current - timedelta(days=90),
        "challenges": current - timedelta(days=2),
        "rate_limits": current - timedelta(days=2),
        "idempotency": current - timedelta(days=30),
        "exports": current - timedelta(days=2),
    }
    predicates = (
        (
            "sessions",
            AuthSession,
            (AuthSession.expires_at < current) | (AuthSession.created_at < cutoffs["sessions"]),
        ),
        (
            "challenges",
            VerificationChallenge,
            VerificationChallenge.created_at < cutoffs["challenges"],
        ),
        ("rate_limits", RateLimitCounter, RateLimitCounter.updated_at < cutoffs["rate_limits"]),
        (
            "idempotency",
            IdempotencyRecord,
            IdempotencyRecord.created_at < cutoffs["idempotency"],
        ),
        (
            "exports",
            ExportJob,
            (ExportJob.expires_at < current) | (ExportJob.created_at < cutoffs["exports"]),
        ),
    )
    counts: dict[str, int] = {}
    with sessions.begin() as session:
        for name, model, predicate in predicates:
            rows = session.execute(
                delete(model).where(predicate).execution_options(synchronize_session=False)
            )
            counts[name] = rows.rowcount or 0
    return counts
