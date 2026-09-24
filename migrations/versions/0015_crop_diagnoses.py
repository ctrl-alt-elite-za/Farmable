"""Durable, consented focus-photo diagnosis jobs (additive)."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0015"
down_revision = "0014"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "crop_diagnoses",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("section_id", sa.Uuid(), nullable=False),
        sa.Column("media_id", sa.Uuid(), nullable=False),
        sa.Column("planting_id", sa.Uuid(), nullable=False),
        sa.Column("planting_version", sa.BigInteger(), nullable=False),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("fingerprint", sa.Text(), nullable=False),
        sa.Column("consent_notice_version", sa.Text(), nullable=False),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("attempts", sa.Integer(), nullable=False),
        sa.Column("error", sa.Text()),
        sa.Column("result", postgresql.JSONB()),
        sa.Column("lease_token", sa.Uuid()),
        sa.Column("lease_expires_at", sa.DateTime(timezone=True)),
        sa.Column("next_attempt_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("withdrawn_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["owner_id"], ["auth_identities.id"], ondelete="CASCADE"),
        sa.ForeignKeyConstraint(["planting_id"], ["plantings.id"]),
        sa.ForeignKeyConstraint(
            ["farm_id", "owner_id"],
            ["farms.id", "farms.owner_id"],
            name="fk_crop_diagnoses_farm_owner",
            ondelete="CASCADE",
        ),
        sa.ForeignKeyConstraint(
            ["section_id", "farm_id", "owner_id"],
            ["sections.id", "sections.farm_id", "sections.owner_id"],
            name="fk_crop_diagnoses_section_farm_owner",
            deferrable=True,
            initially="DEFERRED",
        ),
        sa.ForeignKeyConstraint(
            ["media_id", "farm_id", "owner_id"],
            ["media.id", "media.farm_id", "media.owner_id"],
            name="fk_crop_diagnoses_media_scope",
        ),
        sa.CheckConstraint(
            sa.column("state").in_(("queued", "processing", "ready", "unavailable", "cancelled")),
            name="ck_crop_diagnoses_state",
        ),
        sa.CheckConstraint(sa.column("attempts").between(0, 3), name="ck_crop_diagnoses_attempts"),
    )
    op.create_index("ix_crop_diagnoses_due", "crop_diagnoses", ["state", "next_attempt_at"])
    op.create_index("ix_crop_diagnoses_owner_created", "crop_diagnoses", ["owner_id", "created_at"])


def downgrade():
    # Stop diagnosis submission/workers first; this discards receipts and results,
    # never the source photos or plantings. It cannot erase provider-held copies.
    op.drop_table("crop_diagnoses")
