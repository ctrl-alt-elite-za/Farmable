"""Explicit assistant consent; existing conversations remain unconsented.

Revision ID: 0011
Revises: 0010
"""

import sqlalchemy as sa
from alembic import op

revision = "0011"
down_revision = "0010"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "assistant_consents",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("model", sa.Text(), nullable=False),
        sa.Column("notice_version", sa.Text(), nullable=False),
        sa.Column("granted_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("withdrawn_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(
            ("id", "owner_id"),
            ("assistant_conversations.id", "assistant_conversations.owner_id"),
            ondelete="CASCADE",
            name="fk_assistant_consent_conversation_owner",
        ),
    )
    op.create_index("ix_assistant_consents_owner", "assistant_consents", ["owner_id"])


def downgrade():
    # Disable/drain the assistant first. Removing consent is deliberately lossy.
    op.drop_table("assistant_consents")
