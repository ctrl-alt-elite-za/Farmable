"""Versioned forecast snapshots and serialized activation.

Revision ID: 0007
Revises: 0006
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0007"
down_revision: str | None = "0006"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    document = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")
    op.create_table(
        "forecast_runs",
        sa.Column("id", sa.Text(), nullable=False),
        sa.Column("source_sha256", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("payload", document, nullable=True),
        sa.Column("failed_checks", document, nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.column("status").in_(("staged", "active", "superseded")),
            name="ck_forecast_run_status",
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "uq_forecast_one_active",
        "forecast_runs",
        ["status"],
        unique=True,
        postgresql_where=sa.column("status") == "active",
        sqlite_where=sa.column("status") == "active",
    )
    state = op.create_table(
        "forecast_state",
        sa.Column("id", sa.BigInteger(), autoincrement=False, nullable=False),
        sa.Column("active_run_id", sa.Text(), nullable=True),
        sa.CheckConstraint(sa.column("id") == 1, name="ck_forecast_state_singleton"),
        sa.ForeignKeyConstraint(["active_run_id"], ["forecast_runs.id"]),
        sa.PrimaryKeyConstraint("id"),
    )
    op.bulk_insert(state, [{"id": 1, "active_run_id": None}])


def downgrade() -> None:
    op.drop_table("forecast_state")
    op.drop_index("uq_forecast_one_active", table_name="forecast_runs")
    op.drop_table("forecast_runs")
