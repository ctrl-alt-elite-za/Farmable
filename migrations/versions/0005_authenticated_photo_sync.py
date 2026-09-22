"""authenticated_photo_sync

Revision ID: 0005
Revises: 0004
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0005"
down_revision: str | None = "0004"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Generated from the ORM; expressions replace SQL-string renderings.
    # Only new tables. Runtime migration connection bounds lock/statement waits.
    op.create_table(
        "photo_rates",
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column(
            "hits",
            sa.JSON().with_variant(postgresql.JSONB(astext_type=sa.Text()), "postgresql"),
            nullable=False,
        ),
        sa.ForeignKeyConstraint(
            ["owner_id"],
            ["users.id"],
        ),
        sa.PrimaryKeyConstraint("owner_id"),
    )
    op.create_table(
        "photo_uploads",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("mutation_row_id", sa.Uuid(), nullable=False),
        sa.Column("media_id", sa.Uuid(), nullable=False),
        sa.Column("local_media_id", sa.Uuid(), nullable=False),
        sa.Column("content_type", sa.Text(), nullable=False),
        sa.Column("byte_length", sa.BigInteger(), nullable=False),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("error_code", sa.Text(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.column("content_type").in_(("image/jpeg", "image/png")), name="ck_photo_uploads_type"
        ),
        sa.CheckConstraint(
            sa.column("state").in_(
                ("awaiting_upload", "queued", "processing", "ready", "failed", "expired")
            ),
            name="ck_photo_uploads_state",
        ),
        sa.CheckConstraint(
            sa.column("byte_length").between(1, 5000000), name="ck_photo_uploads_size"
        ),
        sa.CheckConstraint(sa.column("sequence") > 0, name="ck_photo_uploads_sequence"),
        sa.ForeignKeyConstraint(
            ["farm_id", "owner_id"],
            ["farms.id", "farms.owner_id"],
            name="fk_photo_uploads_farm_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["mutation_row_id", "farm_id", "owner_id"],
            ["sync_mutations.id", "sync_mutations.farm_id", "sync_mutations.owner_id"],
            name="fk_photo_uploads_mutation_scope",
        ),
        sa.ForeignKeyConstraint(
            ["section_id", "farm_id", "owner_id"],
            ["sections.id", "sections.farm_id", "sections.owner_id"],
            name="fk_photo_uploads_section_farm_owner",
            initially="DEFERRED",
            deferrable=True,
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("media_id", name="uq_photo_uploads_media"),
        sa.UniqueConstraint("mutation_row_id", name="uq_photo_uploads_mutation"),
        sa.UniqueConstraint("owner_id", "local_media_id", name="uq_photo_uploads_local"),
    )
    op.create_index("ix_photo_uploads_due", "photo_uploads", ["state", "id"], unique=False)
    op.create_table(
        "photo_attempts",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("upload_id", sa.Uuid(), nullable=False),
        sa.Column("sequence", sa.BigInteger(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("form_expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempt_count", sa.BigInteger(), nullable=False),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("lease_token", sa.Uuid(), nullable=True),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("source_generation", sa.Text(), nullable=True),
        sa.Column("clean_generation", sa.Text(), nullable=True),
        sa.Column("clean_sha256", sa.Text(), nullable=True),
        sa.Column("clean_size", sa.BigInteger(), nullable=True),
        sa.Column("width", sa.BigInteger(), nullable=True),
        sa.Column("height", sa.BigInteger(), nullable=True),
        sa.Column("terminal_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cleanup_token", sa.Uuid(), nullable=True),
        sa.Column("cleanup_expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("cleaned_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            sa.column("attempt_count").between(0, 4), name="ck_photo_attempts_count"
        ),
        sa.CheckConstraint(sa.column("sequence") > 0, name="ck_photo_attempts_sequence"),
        sa.ForeignKeyConstraint(
            ["upload_id"],
            ["photo_uploads.id"],
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("upload_id", "sequence", name="uq_photo_attempts_sequence"),
    )
    op.create_index(
        "ix_photo_attempts_cleanup", "photo_attempts", ["cleaned_at", "terminal_at"], unique=False
    )


def downgrade() -> None:
    # Explicit destructive downgrade only. Operational rollback retains tables.
    op.drop_index("ix_photo_attempts_cleanup", table_name="photo_attempts")
    op.drop_table("photo_attempts")
    op.drop_index("ix_photo_uploads_due", table_name="photo_uploads")
    op.drop_table("photo_uploads")
    op.drop_table("photo_rates")
