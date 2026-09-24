"""Separate explicit audio consent and content-free Gemini Live capabilities.

Revision ID: 0014
Revises: 0013
"""

import sqlalchemy as sa
from alembic import op

revision = "0014"
down_revision = "0013"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "assistant_live_consents",
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
            name="fk_assistant_live_consent_owner",
        ),
    )
    op.create_index("ix_assistant_live_consents_owner", "assistant_live_consents", ["owner_id"])
    op.create_table(
        "assistant_live_sessions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("conversation_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("model", sa.Text(), nullable=False),
        sa.Column("state", sa.Text(), nullable=False, server_default="issuing"),
        sa.Column("tool_count", sa.Integer(), nullable=False, server_default="0"),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ("conversation_id", "owner_id"),
            ("assistant_conversations.id", "assistant_conversations.owner_id"),
            ondelete="CASCADE",
            name="fk_assistant_live_session_owner",
        ),
        sa.CheckConstraint(
            sa.column("state").in_(("issuing", "active", "interrupted", "failed")),
            name="ck_assistant_live_session_state",
        ),
        sa.CheckConstraint(
            sa.column("tool_count").between(0, 32), name="ck_assistant_live_tool_count"
        ),
    )
    op.create_index(
        "ix_assistant_live_sessions_owner_expiry",
        "assistant_live_sessions",
        ["owner_id", "expires_at"],
    )


def downgrade():
    # Stop issuance/tool traffic first. This discards receipts, not provider connections.
    op.drop_table("assistant_live_sessions")
    op.drop_table("assistant_live_consents")
