"""export jobs

Revision ID: 0012
Revises: 0011
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0012"
down_revision: str | None = "0011"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "export_jobs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "owner_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("status", sa.Text(), nullable=False, server_default="pending"),
        sa.Column("format", sa.Text(), nullable=False),
        sa.Column("artifact", sa.LargeBinary(), nullable=True),
        sa.Column("download_token_hash", sa.Text(), nullable=True, unique=True),
        sa.Column("error_code", sa.Text(), nullable=True),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=True),
        sa.Column("downloaded_at", sa.DateTime(timezone=True), nullable=True),
        sa.CheckConstraint(
            sa.column("status").in_(["pending", "ready", "failed", "expired"]),
            name="ck_export_jobs_status",
        ),
        sa.CheckConstraint(sa.column("format").in_(["json", "zip"]), name="ck_export_jobs_format"),
        sa.CheckConstraint(
            sa.func.length(sa.column("status")) <= 20, name="ck_export_jobs_status_max_length"
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("format")) <= 4, name="ck_export_jobs_format_max_length"
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("download_token_hash")) <= 64,
            name="ck_export_jobs_download_token_hash_max_length",
        ),
    )
    op.create_index("ix_export_jobs_owner_created", "export_jobs", ["owner_id", "created_at"])


def downgrade() -> None:
    op.drop_index("ix_export_jobs_owner_created", table_name="export_jobs")
    op.drop_table("export_jobs")
