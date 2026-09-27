"""Durable, bounded section erasure jobs (#11).

Revision ID: 0027
Revises: 0026
"""

import sqlalchemy as sa
from alembic import op

revision = "0027"
down_revision = "0026"
branch_labels = None
depends_on = None


def upgrade() -> None:
    op.create_table(
        "section_deletions",
        sa.Column("section_id", sa.Uuid(), primary_key=True),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.Text(), nullable=False, server_default="pending"),
        sa.Column("failures", sa.Integer(), nullable=False, server_default="0"),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("lease_token", sa.Uuid()),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True)),
        sa.Column("error_code", sa.Text()),
        sa.Column("completed_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(
            ("farm_id", "owner_id"),
            ("farms.id", "farms.owner_id"),
            name="fk_section_deletions_farm_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ("section_id", "farm_id", "owner_id"),
            ("sections.id", "sections.farm_id", "sections.owner_id"),
            name="fk_section_deletions_section_farm_owner",
            deferrable=True,
            initially="DEFERRED",
        ),
        sa.CheckConstraint(
            sa.column("status").in_(("pending", "processing", "complete", "failed")),
            name="ck_section_deletions_status",
        ),
        sa.CheckConstraint(
            sa.column("failures").between(0, 4), name="ck_section_deletions_failures"
        ),
    )
    op.create_index("ix_section_deletions_due", "section_deletions", ["status", "next_attempt_at"])


def downgrade() -> None:
    op.drop_index("ix_section_deletions_due", table_name="section_deletions")
    op.drop_table("section_deletions")
