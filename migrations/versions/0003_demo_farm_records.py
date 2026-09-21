"""demo farm records and synchronization metadata

Revision ID: 0003
Revises: 0002
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

SYNC_STATES = ("pending", "synced", "conflict")


def timestamps() -> list[sa.Column]:
    return [
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    ]


def owned_record_columns() -> list[sa.Column]:
    return [
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "farm_id", sa.Uuid(), sa.ForeignKey("farms.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "owner_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        *timestamps(),
        sa.Column("version", sa.BigInteger(), server_default="1", nullable=False),
        sa.Column("sync_state", sa.Text(), server_default="pending", nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    ]


def sync_check(table: str) -> sa.CheckConstraint:
    return sa.CheckConstraint(
        sa.column("sync_state").in_(SYNC_STATES), name=f"ck_{table}_sync_state"
    )


def owned_indexes(table: str, *extra: str) -> None:
    op.create_index(f"ix_{table}_farm_id", table, ["farm_id"])
    op.create_index(f"ix_{table}_owner_id", table, ["owner_id"])
    for column in extra:
        op.create_index(f"ix_{table}_{column}", table, [column])


def upgrade() -> None:
    op.create_table(
        "users",
        sa.Column("id", sa.Uuid(), primary_key=True),
        *timestamps(),
    )
    op.create_table(
        "farms",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "owner_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("name", sa.Text(), nullable=False),
        *timestamps(),
        sa.Column("version", sa.BigInteger(), server_default="1", nullable=False),
        sa.Column("sync_state", sa.Text(), server_default="pending", nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
        sync_check("farms"),
    )
    op.create_index("ix_farms_owner_id", "farms", ["owner_id"])

    op.create_table(
        "sections",
        *owned_record_columns(),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("boundary", sa.JSON(), nullable=True),
        sa.Column("area_m2", sa.Numeric(14, 2), nullable=True),
        sync_check("sections"),
    )
    owned_indexes("sections")

    op.create_table(
        "plantings",
        *owned_record_columns(),
        sa.Column(
            "section_id",
            sa.Uuid(),
            sa.ForeignKey("sections.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("planted_on", sa.Date(), nullable=True),
        sa.Column("is_current", sa.Boolean(), server_default="true", nullable=False),
        sync_check("plantings"),
    )
    owned_indexes("plantings", "section_id")

    op.create_table(
        "media",
        *owned_record_columns(),
        sa.Column(
            "section_id",
            sa.Uuid(),
            sa.ForeignKey("sections.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("local_id", sa.Text(), nullable=False),
        sa.Column("object_key", sa.Text(), nullable=True),
        sa.Column("media_type", sa.Text(), nullable=False),
        sync_check("media"),
        sa.UniqueConstraint("owner_id", "local_id", name="uq_media_owner_local_id"),
    )
    owned_indexes("media", "section_id")

    op.create_table(
        "observations",
        *owned_record_columns(),
        sa.Column(
            "section_id",
            sa.Uuid(),
            sa.ForeignKey("sections.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("type", sa.Text(), nullable=False),
        sa.Column("note", sa.Text(), nullable=False),
        sa.Column("health_status", sa.Text(), nullable=True),
        sa.Column("action_taken", sa.Text(), nullable=True),
        sa.Column(
            "local_media_id",
            sa.Uuid(),
            sa.ForeignKey("media.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("created_by_voice", sa.Boolean(), server_default="false", nullable=False),
        sync_check("observations"),
    )
    owned_indexes("observations", "section_id", "local_media_id")

    op.create_table(
        "farm_tasks",
        *owned_record_columns(),
        sa.Column(
            "section_id",
            sa.Uuid(),
            sa.ForeignKey("sections.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("status", sa.Text(), server_default="pending", nullable=False),
        sa.Column("expected_cost_cents", sa.BigInteger(), nullable=True),
        sync_check("farm_tasks"),
        sa.CheckConstraint(
            sa.column("status").in_(("pending", "in_progress", "done", "cancelled")),
            name="ck_farm_tasks_status",
        ),
    )
    owned_indexes("farm_tasks", "section_id")

    op.create_table(
        "financial_records",
        *owned_record_columns(),
        sa.Column(
            "section_id",
            sa.Uuid(),
            sa.ForeignKey("sections.id", ondelete="SET NULL"),
            nullable=True,
        ),
        sa.Column("type", sa.Text(), nullable=False),
        sa.Column("category", sa.Text(), nullable=False),
        sa.Column("amount_cents", sa.BigInteger(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        sync_check("financial_records"),
        sa.CheckConstraint(
            sa.column("type").in_(("expense", "income")), name="ck_financial_records_type"
        ),
        sa.CheckConstraint(
            sa.column("amount_cents") >= 0, name="ck_financial_records_amount_nonnegative"
        ),
    )
    owned_indexes("financial_records", "section_id")

    op.create_table(
        "saved_plans",
        *owned_record_columns(),
        sa.Column(
            "section_id",
            sa.Uuid(),
            sa.ForeignKey("sections.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("status", sa.Text(), server_default="saved", nullable=False),
        sa.Column("plan", sa.JSON(), nullable=False),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        sync_check("saved_plans"),
        sa.CheckConstraint(
            sa.column("status").in_(("saved", "approved", "rejected")),
            name="ck_saved_plans_status",
        ),
    )
    owned_indexes("saved_plans", "section_id")

    op.create_table(
        "sync_mutations",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("mutation_id", sa.Uuid(), nullable=False),
        sa.Column(
            "farm_id", sa.Uuid(), sa.ForeignKey("farms.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "owner_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("operation", sa.Text(), nullable=False),
        sa.Column("record_type", sa.Text(), nullable=False),
        sa.Column("record_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.UniqueConstraint("mutation_id", name="uq_sync_mutations_mutation_id"),
    )
    owned_indexes("sync_mutations", "record_id")

    op.create_table(
        "sync_changes",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "farm_id", sa.Uuid(), sa.ForeignKey("farms.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "owner_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column(
            "mutation_id",
            sa.Uuid(),
            sa.ForeignKey("sync_mutations.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("record_type", sa.Text(), nullable=False),
        sa.Column("record_id", sa.Uuid(), nullable=False),
        sa.Column("operation", sa.Text(), nullable=False),
        sa.Column("version", sa.BigInteger(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    owned_indexes("sync_changes", "mutation_id", "record_id")


def downgrade() -> None:
    for table in (
        "sync_changes",
        "sync_mutations",
        "saved_plans",
        "financial_records",
        "farm_tasks",
        "observations",
        "media",
        "plantings",
        "sections",
        "farms",
        "users",
    ):
        op.drop_table(table)
