"""Rounded-grid weather outbox and climatology; additive, no existing data changes.

Revision ID: 0008
Revises: 0007
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0008"
down_revision: str | None = "0007"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "weather_jobs",
        sa.Column("id", sa.Text(), nullable=False),
        sa.Column("latitude_tenths", sa.Integer(), nullable=False),
        sa.Column("longitude_tenths", sa.Integer(), nullable=False),
        sa.Column("first_year", sa.Integer(), nullable=False),
        sa.Column("last_year", sa.Integer(), nullable=False),
        sa.Column("policy_hash", sa.Text(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("attempt_count", sa.Integer(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("lease_token", sa.Uuid(), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("completed_kind", sa.Text(), nullable=True),
        sa.Column("error_code", sa.Text(), nullable=True),
        sa.CheckConstraint(sa.column("latitude_tenths").between(-900, 900), name="ck_weather_lat"),
        sa.CheckConstraint(
            sa.column("longitude_tenths").between(-1800, 1799), name="ck_weather_lon"
        ),
        sa.CheckConstraint(
            sa.column("last_year") - sa.column("first_year") == 14, name="ck_weather_years"
        ),
        sa.CheckConstraint(
            sa.column("status").in_(("pending", "processing", "ready")), name="ck_weather_status"
        ),
        sa.PrimaryKeyConstraint("id"),
    )
    op.create_index(
        "ix_weather_due", "weather_jobs", ["policy_hash", "last_year", "status", "next_attempt_at"]
    )
    op.create_table(
        "weather_risk_climatology",
        sa.Column("job_id", sa.Text(), nullable=False),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("plant_month", sa.Integer(), nullable=False),
        sa.Column(
            "payload", sa.JSON().with_variant(postgresql.JSONB(), "postgresql"), nullable=False
        ),
        sa.Column("computed_at", sa.DateTime(timezone=True), nullable=False),
        sa.CheckConstraint(sa.column("plant_month").between(1, 12), name="ck_weather_month"),
        sa.ForeignKeyConstraint(["job_id"], ["weather_jobs.id"]),
        sa.PrimaryKeyConstraint("job_id", "crop", "plant_month"),
    )


def downgrade() -> None:
    op.drop_table("weather_risk_climatology")
    op.drop_index("ix_weather_due", table_name="weather_jobs")
    op.drop_table("weather_jobs")
