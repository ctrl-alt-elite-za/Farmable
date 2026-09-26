"""Let a lost refresh response be retried without signing out every device.

Revision ID: 0028
Revises: 0027
"""

import sqlalchemy as sa
from alembic import op

revision = "0028"
down_revision = "0027"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("auth_sessions", sa.Column("replaced_by_id", sa.Uuid(), nullable=True))
    op.add_column("auth_sessions", sa.Column("used_at", sa.DateTime(timezone=True), nullable=True))


def downgrade():
    op.drop_column("auth_sessions", "used_at")
    op.drop_column("auth_sessions", "replaced_by_id")
