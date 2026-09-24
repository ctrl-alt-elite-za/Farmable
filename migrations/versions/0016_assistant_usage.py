"""Content-free, per-exchange usage receipts; no historical costs invented."""

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision = "0016"
down_revision = "0015"
branch_labels = None
depends_on = None


def upgrade():
    op.create_table(
        "assistant_turn_costs",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("turn_id", sa.Uuid(), unique=True),
        sa.Column("day", sa.Date(), nullable=False),
        sa.Column("policy", sa.Text(), nullable=False),
        sa.Column("reserved_micro_usd", sa.BigInteger(), nullable=False),
        sa.Column("settled_micro_usd", sa.BigInteger()),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("error", sa.Text()),
        sa.Column("next_check_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("settled_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["turn_id"], ["assistant_turns.id"], ondelete="SET NULL"),
        sa.CheckConstraint(
            sa.column("state").in_(("reserved", "unknown", "settled")),
            name="ck_assistant_cost_state",
        ),
        sa.CheckConstraint(sa.column("reserved_micro_usd") >= 0, name="ck_assistant_cost_reserved"),
        sa.CheckConstraint(sa.column("settled_micro_usd") >= 0, name="ck_assistant_cost_settled"),
    )
    op.create_index("ix_assistant_costs_due", "assistant_turn_costs", ["state", "next_check_at"])
    op.create_table(
        "assistant_model_calls",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("cost_id", sa.Uuid(), nullable=False),
        sa.Column("turn_id", sa.Uuid()),
        sa.Column("round_index", sa.BigInteger(), nullable=False),
        sa.Column("billing_project", sa.Text()),
        sa.Column("model", sa.Text(), nullable=False),
        sa.Column("response_model", sa.Text()),
        sa.Column("data_kind", sa.Text(), nullable=False),
        sa.Column("state", sa.Text(), nullable=False),
        sa.Column("error", sa.Text()),
        sa.Column("usage", postgresql.JSONB(), nullable=False),
        sa.Column("pricing", postgresql.JSONB()),
        sa.Column("estimated_micro_usd", sa.BigInteger()),
        sa.Column("cache_mode", sa.Text(), nullable=False),
        sa.Column("cache_cost_micro_usd", sa.BigInteger()),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), nullable=False, server_default=sa.func.now()
        ),
        sa.Column("finished_at", sa.DateTime(timezone=True)),
        sa.ForeignKeyConstraint(["turn_id"], ["assistant_turns.id"], ondelete="SET NULL"),
        sa.ForeignKeyConstraint(["cost_id"], ["assistant_turn_costs.id"], ondelete="CASCADE"),
        sa.UniqueConstraint("turn_id", "round_index", name="uq_assistant_call_round"),
        sa.CheckConstraint(sa.column("round_index").between(0, 3), name="ck_assistant_call_round"),
        sa.CheckConstraint(
            sa.column("state").in_(("started", "unknown", "unpriced", "priced")),
            name="ck_assistant_call_state",
        ),
        sa.CheckConstraint(sa.column("estimated_micro_usd") >= 0, name="ck_assistant_call_cost"),
        sa.CheckConstraint(
            sa.column("data_kind").in_(("synthetic", "provider")),
            name="ck_assistant_call_kind",
        ),
    )
    op.create_index(
        "ix_assistant_calls_project_created",
        "assistant_model_calls",
        ["billing_project", "created_at"],
    )
    op.create_index("ix_assistant_calls_cost", "assistant_model_calls", ["cost_id"])


def downgrade():
    # Disable/drain generation first. Loses receipts, not chat or provider charges.
    op.drop_table("assistant_model_calls")
    op.drop_table("assistant_turn_costs")
