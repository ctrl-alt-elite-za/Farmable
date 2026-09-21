"""production farm records and synchronization metadata

Revision ID: 0003
Revises: 0002
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

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
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        *timestamps(),
        sa.Column("version", sa.BigInteger(), server_default="1", nullable=False),
        sa.Column("sync_state", sa.Text(), server_default="pending", nullable=False),
        sa.Column("deleted_at", sa.DateTime(timezone=True), nullable=True),
    ]


def owned_constraints(table: str) -> list[sa.Constraint]:
    return [
        sa.ForeignKeyConstraint(
            ("farm_id", "owner_id"),
            ("farms.id", "farms.owner_id"),
            name=f"fk_{table}_farm_owner",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint(sa.column("version") > 0, name=f"ck_{table}_version_positive"),
        sa.CheckConstraint(sa.column("sync_state").in_(SYNC_STATES), name=f"ck_{table}_sync_state"),
        max_length("sync_state", table, 20),
    ]


def section_owner_fk(table: str) -> sa.ForeignKeyConstraint:
    return sa.ForeignKeyConstraint(
        ("section_id", "farm_id", "owner_id"),
        ("sections.id", "sections.farm_id", "sections.owner_id"),
        name=f"fk_{table}_section_farm_owner",
        deferrable=True,
        initially="DEFERRED",
    )


def nonblank(name: str, table: str) -> sa.CheckConstraint:
    return sa.CheckConstraint(
        sa.func.length(sa.func.trim(sa.column(name))) > 0,
        name=f"ck_{table}_{name}_nonblank",
    )


def max_length(name: str, table: str, maximum: int) -> sa.CheckConstraint:
    return sa.CheckConstraint(
        sa.func.length(sa.column(name)) <= maximum,
        name=f"ck_{table}_{name}_max_length",
    )


def upgrade() -> None:
    json_document = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")

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
        sa.CheckConstraint(sa.column("version") > 0, name="ck_farms_version_positive"),
        sa.CheckConstraint(sa.column("sync_state").in_(SYNC_STATES), name="ck_farms_sync_state"),
        nonblank("name", "farms"),
        max_length("sync_state", "farms", 20),
        max_length("name", "farms", 200),
        sa.UniqueConstraint("id", "owner_id", name="uq_farms_id_owner_id"),
    )
    op.create_index("ix_farms_owner_active", "farms", ["owner_id", "deleted_at"])

    op.create_table(
        "sections",
        *owned_record_columns(),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("boundary", json_document, nullable=True),
        sa.Column("area_m2", sa.Numeric(14, 2), nullable=True),
        *owned_constraints("sections"),
        nonblank("name", "sections"),
        max_length("name", "sections", 200),
        sa.CheckConstraint(
            sa.column("area_m2").is_(None) | (sa.column("area_m2") > 0),
            name="ck_sections_area_positive",
        ),
        sa.UniqueConstraint("id", "farm_id", "owner_id", name="uq_sections_id_farm_owner"),
    )
    op.create_index(
        "ix_sections_owner_farm_active", "sections", ["owner_id", "farm_id", "deleted_at"]
    )

    op.create_table(
        "plantings",
        *owned_record_columns(),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("planted_on", sa.Date(), nullable=True),
        sa.Column("is_current", sa.Boolean(), server_default="true", nullable=False),
        *owned_constraints("plantings"),
        section_owner_fk("plantings"),
        nonblank("crop", "plantings"),
        max_length("crop", "plantings", 100),
    )
    op.create_index(
        "ix_plantings_owner_farm_active", "plantings", ["owner_id", "farm_id", "deleted_at"]
    )
    current_planting = sa.column("is_current").is_(True) & sa.column("deleted_at").is_(None)
    op.create_index(
        "uq_plantings_current_section",
        "plantings",
        ["section_id"],
        unique=True,
        postgresql_where=current_planting,
        sqlite_where=current_planting,
    )

    op.create_table(
        "media",
        *owned_record_columns(),
        sa.Column("section_id", sa.Uuid(), nullable=True),
        sa.Column("local_id", sa.Text(), nullable=False),
        sa.Column("object_key", sa.Text(), nullable=True),
        sa.Column("media_type", sa.Text(), nullable=False),
        *owned_constraints("media"),
        section_owner_fk("media"),
        nonblank("local_id", "media"),
        nonblank("media_type", "media"),
        max_length("local_id", "media", 255),
        max_length("object_key", "media", 1024),
        max_length("media_type", "media", 100),
        sa.CheckConstraint(
            sa.column("object_key").is_(None)
            | (sa.func.length(sa.func.trim(sa.column("object_key"))) > 0),
            name="ck_media_object_key_nonblank",
        ),
        sa.UniqueConstraint("id", "farm_id", "owner_id", name="uq_media_id_farm_owner"),
        sa.UniqueConstraint("owner_id", "local_id", name="uq_media_owner_local_id"),
    )
    op.create_index("ix_media_owner_farm_active", "media", ["owner_id", "farm_id", "deleted_at"])
    op.create_index("ix_media_section_id", "media", ["section_id"])

    op.create_table(
        "observations",
        *owned_record_columns(),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("type", sa.Text(), nullable=False),
        sa.Column("note", sa.Text(), nullable=False),
        sa.Column("health_status", sa.Text(), nullable=True),
        sa.Column("action_taken", sa.Text(), nullable=True),
        sa.Column("local_media_id", sa.Uuid(), nullable=True),
        sa.Column("created_by_voice", sa.Boolean(), server_default="false", nullable=False),
        *owned_constraints("observations"),
        section_owner_fk("observations"),
        sa.ForeignKeyConstraint(
            ("local_media_id", "farm_id", "owner_id"),
            ("media.id", "media.farm_id", "media.owner_id"),
            name="fk_observations_media_farm_owner",
            deferrable=True,
            initially="DEFERRED",
        ),
        nonblank("type", "observations"),
        nonblank("note", "observations"),
        max_length("type", "observations", 100),
        max_length("note", "observations", 10000),
        max_length("health_status", "observations", 100),
        max_length("action_taken", "observations", 10000),
    )
    op.create_index(
        "ix_observations_owner_farm_active",
        "observations",
        ["owner_id", "farm_id", "deleted_at"],
    )
    op.create_index(
        "ix_observations_section_created",
        "observations",
        ["owner_id", "farm_id", "section_id", "created_at"],
    )

    op.create_table(
        "farm_tasks",
        *owned_record_columns(),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("title", sa.Text(), nullable=False),
        sa.Column("description", sa.Text(), nullable=True),
        sa.Column("due_date", sa.Date(), nullable=False),
        sa.Column("status", sa.Text(), server_default="pending", nullable=False),
        sa.Column("expected_cost_cents", sa.BigInteger(), nullable=True),
        *owned_constraints("farm_tasks"),
        section_owner_fk("farm_tasks"),
        sa.CheckConstraint(
            sa.column("status").in_(("pending", "in_progress", "done", "cancelled")),
            name="ck_farm_tasks_status",
        ),
        sa.CheckConstraint(
            sa.column("expected_cost_cents").is_(None) | (sa.column("expected_cost_cents") >= 0),
            name="ck_farm_tasks_expected_cost_nonnegative",
        ),
        nonblank("title", "farm_tasks"),
        max_length("title", "farm_tasks", 200),
        max_length("description", "farm_tasks", 10000),
        max_length("status", "farm_tasks", 20),
    )
    op.create_index(
        "ix_farm_tasks_owner_farm_active",
        "farm_tasks",
        ["owner_id", "farm_id", "deleted_at"],
    )
    op.create_index(
        "ix_farm_tasks_section_due",
        "farm_tasks",
        ["owner_id", "farm_id", "section_id", "due_date"],
    )

    op.create_table(
        "financial_records",
        *owned_record_columns(),
        sa.Column("section_id", sa.Uuid(), nullable=True),
        sa.Column("type", sa.Text(), nullable=False),
        sa.Column("category", sa.Text(), nullable=False),
        sa.Column("amount_cents", sa.BigInteger(), nullable=False),
        sa.Column("date", sa.Date(), nullable=False),
        sa.Column("note", sa.Text(), nullable=True),
        *owned_constraints("financial_records"),
        section_owner_fk("financial_records"),
        sa.CheckConstraint(
            sa.column("type").in_(("expense", "income")), name="ck_financial_records_type"
        ),
        sa.CheckConstraint(
            sa.column("amount_cents") >= 0, name="ck_financial_records_amount_nonnegative"
        ),
        nonblank("category", "financial_records"),
        max_length("type", "financial_records", 20),
        max_length("category", "financial_records", 100),
        max_length("note", "financial_records", 10000),
    )
    op.create_index(
        "ix_financial_records_owner_farm_active",
        "financial_records",
        ["owner_id", "farm_id", "deleted_at"],
    )
    op.create_index(
        "ix_financial_records_section_date",
        "financial_records",
        ["owner_id", "farm_id", "section_id", "date"],
    )

    op.create_table(
        "saved_plans",
        *owned_record_columns(),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("status", sa.Text(), server_default="saved", nullable=False),
        sa.Column("plan", json_document, nullable=False),
        sa.Column("approved_at", sa.DateTime(timezone=True), nullable=True),
        *owned_constraints("saved_plans"),
        section_owner_fk("saved_plans"),
        sa.CheckConstraint(
            sa.column("status").in_(("saved", "approved", "rejected")),
            name="ck_saved_plans_status",
        ),
        max_length("status", "saved_plans", 20),
    )
    op.create_index(
        "ix_saved_plans_owner_farm_active",
        "saved_plans",
        ["owner_id", "farm_id", "deleted_at"],
    )
    op.create_index("ix_saved_plans_section_id", "saved_plans", ["section_id"])

    op.create_table(
        "sync_mutations",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("mutation_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("operation", sa.Text(), nullable=False),
        sa.Column("record_type", sa.Text(), nullable=False),
        sa.Column("record_id", sa.Uuid(), nullable=False),
        sa.Column("request_fingerprint", sa.Text(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ("farm_id", "owner_id"),
            ("farms.id", "farms.owner_id"),
            name="fk_sync_mutations_farm_owner",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint(
            sa.column("request_fingerprint").regexp_match("^[0-9a-f]{64}$"),
            name="ck_sync_mutations_request_fingerprint_hex",
        ),
        nonblank("operation", "sync_mutations"),
        nonblank("record_type", "sync_mutations"),
        max_length("operation", "sync_mutations", 20),
        max_length("record_type", "sync_mutations", 100),
        sa.UniqueConstraint("mutation_id", name="uq_sync_mutations_mutation_id"),
        sa.UniqueConstraint("id", "farm_id", "owner_id", name="uq_sync_mutations_id_farm_owner"),
    )
    op.create_index("ix_sync_mutations_owner_farm", "sync_mutations", ["owner_id", "farm_id"])
    op.create_index("ix_sync_mutations_record", "sync_mutations", ["record_type", "record_id"])

    op.create_table(
        "sync_changes",
        sa.Column(
            "id",
            sa.BigInteger().with_variant(sa.Integer(), "sqlite"),
            sa.Identity(),
            primary_key=True,
        ),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("mutation_id", sa.Uuid(), nullable=False),
        sa.Column("record_type", sa.Text(), nullable=False),
        sa.Column("record_id", sa.Uuid(), nullable=False),
        sa.Column("operation", sa.Text(), nullable=False),
        sa.Column("version", sa.BigInteger(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ("farm_id", "owner_id"),
            ("farms.id", "farms.owner_id"),
            name="fk_sync_changes_farm_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ("mutation_id", "farm_id", "owner_id"),
            ("sync_mutations.id", "sync_mutations.farm_id", "sync_mutations.owner_id"),
            name="fk_sync_changes_mutation_farm_owner",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint(sa.column("version") > 0, name="ck_sync_changes_version_positive"),
        nonblank("operation", "sync_changes"),
        nonblank("record_type", "sync_changes"),
        max_length("operation", "sync_changes", 20),
        max_length("record_type", "sync_changes", 100),
    )
    op.create_index(
        "ix_sync_changes_owner_farm_cursor",
        "sync_changes",
        ["owner_id", "farm_id", "id"],
    )
    op.create_index("ix_sync_changes_mutation_id", "sync_changes", ["mutation_id"])
    op.create_index("ix_sync_changes_record", "sync_changes", ["record_type", "record_id"])


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
