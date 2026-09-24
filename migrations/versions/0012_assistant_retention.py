"""Thirty-day chat-content retention markers and bounded cleanup index.

Revision ID: 0012
Revises: 0011
"""

import sqlalchemy as sa
from alembic import op

revision = "0012"
down_revision = "0011"
branch_labels = None
depends_on = None


def upgrade():
    op.add_column("assistant_turns", sa.Column("content_deleted_at", sa.DateTime(timezone=True)))
    op.create_index(
        "ix_assistant_turns_retention",
        "assistant_turns",
        ["content_deleted_at", "created_at", "id"],
    )


def downgrade():
    # Deleted message content cannot be restored by a schema downgrade.
    op.drop_index("ix_assistant_turns_retention", table_name="assistant_turns")
    op.drop_column("assistant_turns", "content_deleted_at")
