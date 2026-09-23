"""durable rate-limit counters and idempotency records

Revision ID: 0010
Revises: 0009
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Additive only: two new, empty tables. No existing table is altered.
    op.create_table(
        "rate_limit_counters",
        sa.Column("scope", sa.Text(), primary_key=True),
        sa.Column("subject_hash", sa.Text(), primary_key=True),
        sa.Column("hits", sa.JSON(), nullable=False),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.func.length(sa.func.trim(sa.column("scope"))) > 0,
            name="ck_rate_limit_counters_scope_nonblank",
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("scope")) <= 40, name="ck_rate_limit_counters_scope_max_length"
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("subject_hash")) <= 64,
            name="ck_rate_limit_counters_subject_hash_max_length",
        ),
    )
    op.create_table(
        "idempotency_records",
        sa.Column("route", sa.Text(), primary_key=True),
        sa.Column("idempotency_key", sa.Text(), primary_key=True),
        sa.Column("request_fingerprint", sa.Text(), nullable=False),
        sa.Column("status_code", sa.Integer(), nullable=False),
        sa.Column("response_body", sa.JSON(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.func.length(sa.func.trim(sa.column("route"))) > 0,
            name="ck_idempotency_records_route_nonblank",
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("route")) <= 60, name="ck_idempotency_records_route_max_length"
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("idempotency_key")) <= 200,
            name="ck_idempotency_records_idempotency_key_max_length",
        ),
        sa.CheckConstraint(
            sa.column("request_fingerprint").regexp_match("^[0-9a-f]{64}$"),
            name="ck_idempotency_records_request_fingerprint_hex",
        ),
    )


def downgrade() -> None:
    # Deliberate and lossy: drops every persisted counter/idempotency record.
    # Safe because both tables only ever hold derived, reconstructable state.
    op.drop_table("idempotency_records")
    op.drop_table("rate_limit_counters")
