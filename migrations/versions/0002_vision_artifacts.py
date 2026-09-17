"""vision model and formula registry

Revision ID: 0002
Revises: 0001
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0002"
down_revision: str | None = "0001"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "detector_models",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("version", sa.String(length=128), nullable=False),
        sa.Column("artifact_uri", sa.String(length=1024), nullable=False),
        sa.Column("artifact_sha256", sa.String(length=64), nullable=False),
        sa.Column("metrics", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
        sa.UniqueConstraint("version"),
    )
    op.create_index("ix_detector_models_version", "detector_models", ["version"], unique=False)
    op.create_table(
        "weight_formulas",
        sa.Column("id", sa.Integer(), primary_key=True),
        sa.Column("crop", sa.String(length=32), nullable=False),
        sa.Column("version", sa.String(length=128), nullable=False),
        sa.Column("formula", sa.JSON(), nullable=False),
        sa.Column("created_at", sa.DateTime(timezone=True), server_default=sa.func.now()),
    )


def downgrade() -> None:
    op.drop_table("weight_formulas")
    op.drop_index("ix_detector_models_version", table_name="detector_models")
    op.drop_table("detector_models")
