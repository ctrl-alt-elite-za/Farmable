"""Expire abandoned login admission; drain old API workers before rollout.

Revision ID: 0017
Revises: 0016
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0017"
down_revision = "0016"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column(
        "rate_limit_counters",
        sa.Column(
            "login_leases",
            sa.JSON().with_variant(postgresql.JSONB(), "postgresql"),
            nullable=False,
            server_default="{}",
        ),
    )


def downgrade():
    # Drain login traffic first; this removes the new request fencing metadata.
    op.drop_column("rate_limit_counters", "login_leases")
