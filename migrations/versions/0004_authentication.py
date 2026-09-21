"""authentication identities, challenges and hashed sessions

Revision ID: 0004
Revises: 0003
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0004"
down_revision: str | None = "0003"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Only new, empty tables are indexed/validated. Existing users and ownership
    # records are not altered or backfilled. The FK still needs a short metadata
    # lock; migrations/env.py configures bounded lock and statement waits.
    op.create_table(
        "auth_identities",
        sa.Column("id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), primary_key=True),
        sa.Column("first_name", sa.Text(), nullable=False),
        sa.Column("surname", sa.Text(), nullable=False),
        sa.Column("phone", sa.Text(), nullable=False),
        sa.Column("email", sa.Text(), nullable=False),
        sa.Column("password_hash", sa.Text(), nullable=False),
        sa.Column("phone_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column("email_verified", sa.Boolean(), server_default="false", nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.UniqueConstraint("email", name="uq_auth_identities_email"),
        sa.UniqueConstraint("phone", name="uq_auth_identities_phone"),
        sa.CheckConstraint(
            sa.func.length(sa.func.trim(sa.column("first_name"))) > 0,
            name="ck_auth_identities_first_name_nonblank",
        ),
        sa.CheckConstraint(
            sa.func.length(sa.func.trim(sa.column("surname"))) > 0,
            name="ck_auth_identities_surname_nonblank",
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("first_name")) <= 100,
            name="ck_auth_identities_first_name_max_length",
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("surname")) <= 100,
            name="ck_auth_identities_surname_max_length",
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("phone")) <= 32, name="ck_auth_identities_phone_max_length"
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("email")) <= 320, name="ck_auth_identities_email_max_length"
        ),
    )

    op.create_table(
        "verification_challenges",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("auth_identities.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("channel", sa.Text(), nullable=False),
        sa.Column("code_hash", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.BigInteger(), server_default="0", nullable=False),
        sa.Column("consumed_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.column("channel").in_(("phone", "email")), name="ck_verification_channel"
        ),
    )
    op.create_index(
        "ix_verification_challenges_user_channel",
        "verification_challenges",
        ["user_id", "channel", "expires_at"],
    )
    op.create_table(
        "auth_sessions",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("auth_identities.id", ondelete="CASCADE"),
            nullable=False,
        ),
        sa.Column("access_token_hash", sa.Text(), nullable=False),
        sa.Column("refresh_token_hash", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("revoked_at", sa.DateTime(timezone=True)),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
    )
    op.create_index(
        "ix_auth_sessions_access_token_hash", "auth_sessions", ["access_token_hash"], unique=True
    )
    op.create_index(
        "ix_auth_sessions_refresh_token_hash", "auth_sessions", ["refresh_token_hash"], unique=True
    )
    op.create_index(
        "ix_auth_sessions_user_active", "auth_sessions", ["user_id", "revoked_at", "expires_at"]
    )


def downgrade() -> None:
    op.drop_table("auth_sessions")
    op.drop_table("verification_challenges")
    op.drop_table("auth_identities")
