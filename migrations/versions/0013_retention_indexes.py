"""retention indexes for security artifacts

Revision ID: 0013
Revises: 0012
"""

from collections.abc import Sequence

from alembic import op

revision: str = "0013"
down_revision: str | None = "0012"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_index("ix_auth_sessions_retention", "auth_sessions", ["expires_at", "created_at"])
    op.create_index(
        "ix_verification_challenges_retention", "verification_challenges", ["created_at"]
    )
    op.create_index("ix_idempotency_records_retention", "idempotency_records", ["created_at"])
    op.create_index("ix_rate_limit_counters_retention", "rate_limit_counters", ["updated_at"])
    op.create_index("ix_export_jobs_retention", "export_jobs", ["expires_at", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_export_jobs_retention", table_name="export_jobs")
    op.drop_index("ix_rate_limit_counters_retention", table_name="rate_limit_counters")
    op.drop_index("ix_idempotency_records_retention", table_name="idempotency_records")
    op.drop_index("ix_verification_challenges_retention", table_name="verification_challenges")
    op.drop_index("ix_auth_sessions_retention", table_name="auth_sessions")
