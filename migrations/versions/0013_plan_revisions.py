"""Add plan snapshots without rewriting existing plans or claiming lost history.

Revision ID: 0013
Revises: 0012
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0013"
down_revision = "0012"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "plan_revisions",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("plan_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("version", sa.BigInteger(), nullable=False),
        sa.Column("origin", sa.Text(), nullable=False),
        sa.Column(
            "snapshot", sa.JSON().with_variant(postgresql.JSONB(), "postgresql"), nullable=False
        ),
        sa.Column(
            "recorded_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.ForeignKeyConstraint(["plan_id"], ["saved_plans.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(
            ["farm_id", "owner_id"],
            ["farms.id", "farms.owner_id"],
            name="fk_plan_revisions_farm_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["section_id", "farm_id", "owner_id"],
            ["sections.id", "sections.farm_id", "sections.owner_id"],
            name="fk_plan_revisions_section_farm_owner",
            deferrable=True,
            initially="DEFERRED",
        ),
        sa.UniqueConstraint("plan_id", "version", name="uq_plan_revisions_plan_version"),
        sa.CheckConstraint(sa.column("version") > 0, name="ck_plan_revisions_version_positive"),
        sa.CheckConstraint(
            sa.column("origin").in_(("baseline", "manual", "planner_confirmation")),
            name="ck_plan_revisions_origin",
        ),
    )
    op.create_index("ix_plan_revisions_owner_farm", "plan_revisions", ["owner_id", "farm_id"])


def downgrade():
    # Irreversibly discards history, but does not alter the current saved plans.
    op.drop_index("ix_plan_revisions_owner_farm", table_name="plan_revisions")
    op.drop_table("plan_revisions")
