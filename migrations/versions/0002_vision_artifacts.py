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
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("version", sa.Text(), nullable=False),
        sa.Column("artifact_uri", sa.Text(), nullable=False),
        sa.Column("artifact_sha256", sa.Text(), nullable=False),
        sa.Column("metrics", sa.JSON(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.UniqueConstraint("version", name="uq_detector_models_version"),
        sa.CheckConstraint(
            sa.column("artifact_sha256").regexp_match("^[0-9a-f]{64}$"),
            name="ck_detector_models_artifact_sha256_hex",
        ),
    )
    op.create_table(
        "weight_formulas",
        sa.Column("id", sa.BigInteger(), sa.Identity(), primary_key=True),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("version", sa.Text(), nullable=False),
        sa.Column("formula", sa.JSON(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.UniqueConstraint("crop", "version", name="uq_weight_formulas_crop_version"),
        sa.CheckConstraint(
            sa.column("crop").in_(["cabbage", "tomato"]), name="ck_weight_formulas_weighed_crop"
        ),
    )


def downgrade() -> None:
    op.drop_table("weight_formulas")
    op.drop_table("detector_models")
