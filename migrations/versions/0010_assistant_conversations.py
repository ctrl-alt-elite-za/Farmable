"""Durable, owner-scoped conversations and serialized usage admission.

Revision ID: 0010
Revises: 0009
"""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0010"
down_revision = "0009"
branch_labels = None
depends_on = None


def upgrade():
    document = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")
    op.create_table(
        "assistant_conversations",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "owner_id",
            sa.Uuid(),
            sa.ForeignKey("auth_identities.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.ForeignKeyConstraint(
            ("farm_id", "owner_id"),
            ("farms.id", "farms.owner_id"),
            name="fk_assistant_conversations_farm_owner",
            ondelete="CASCADE",
        ),
        sa.UniqueConstraint("id", "owner_id", name="uq_assistant_conversation_owner"),
    )
    op.create_index("ix_assistant_conversations_owner", "assistant_conversations", ["owner_id"])
    op.create_table(
        "assistant_turns",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("conversation_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("message", sa.Text(), nullable=False),
        sa.Column("reply", sa.Text(), nullable=False, server_default=""),
        sa.Column("status", sa.Text(), nullable=False),
        sa.Column("error", sa.Text()),
        sa.Column("tools", document, nullable=False),
        sa.Column("usage", document, nullable=False),
        sa.Column("model", sa.Text(), nullable=False),
        sa.Column("policy", sa.Text(), nullable=False),
        sa.Column("reserved_micro_usd", sa.BigInteger(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column("deadline", sa.DateTime(timezone=True), nullable=False),
        sa.ForeignKeyConstraint(
            ("conversation_id", "owner_id"),
            ("assistant_conversations.id", "assistant_conversations.owner_id"),
            name="fk_assistant_turn_conversation_owner",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint(
            sa.column("status").in_(("running", "completed", "interrupted", "failed")),
            name="ck_assistant_turn_status",
        ),
        sa.CheckConstraint(
            sa.column("reserved_micro_usd") >= 0, name="ck_assistant_turn_reservation"
        ),
    )
    op.create_index(
        "ix_assistant_turns_history", "assistant_turns", ["conversation_id", "created_at", "id"]
    )
    op.create_index(
        "ix_assistant_turns_owner_created", "assistant_turns", ["owner_id", "created_at"]
    )
    op.create_table(
        "assistant_budget",
        sa.Column("id", sa.BigInteger(), primary_key=True, autoincrement=False),
        sa.Column("day", sa.Date()),
        sa.Column("policy", sa.Text()),
        sa.Column("reserved_micro_usd", sa.BigInteger(), nullable=False, server_default="0"),
        sa.CheckConstraint(sa.column("id") == 1, name="ck_assistant_budget_singleton"),
        sa.CheckConstraint(
            sa.column("reserved_micro_usd") >= 0, name="ck_assistant_budget_nonnegative"
        ),
    )
    op.bulk_insert(sa.table("assistant_budget", sa.column("id", sa.BigInteger())), [{"id": 1}])


def downgrade():
    # Explicitly lossy: conversation history and usage reservations are removed.
    op.drop_table("assistant_turns")
    op.drop_table("assistant_conversations")
    op.drop_table("assistant_budget")
