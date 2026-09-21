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
    # Existing farm records predate authentication. Nullable values preserve those
    # owners without inventing duplicate credentials; AuthService always supplies them.
    op.add_column("users", sa.Column("first_name", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("surname", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("phone", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("email", sa.Text(), nullable=True))
    op.add_column("users", sa.Column("password_hash", sa.Text(), nullable=True))
    op.add_column(
        "users", sa.Column("phone_verified", sa.Boolean(), server_default="false", nullable=False)
    )
    op.add_column(
        "users", sa.Column("email_verified", sa.Boolean(), server_default="false", nullable=False)
    )
    op.create_unique_constraint("uq_users_email", "users", ["email"])
    op.create_unique_constraint("uq_users_phone", "users", ["phone"])
    op.create_check_constraint(
        "ck_users_first_name_nonblank",
        "users",
        sa.func.length(sa.func.trim(sa.column("first_name"))) > 0,
    )
    op.create_check_constraint(
        "ck_users_surname_nonblank", "users", sa.func.length(sa.func.trim(sa.column("surname"))) > 0
    )
    op.create_check_constraint(
        "ck_users_first_name_max_length", "users", sa.func.length(sa.column("first_name")) <= 100
    )
    op.create_check_constraint(
        "ck_users_surname_max_length", "users", sa.func.length(sa.column("surname")) <= 100
    )
    op.create_check_constraint(
        "ck_users_phone_max_length", "users", sa.func.length(sa.column("phone")) <= 32
    )
    op.create_check_constraint(
        "ck_users_email_max_length", "users", sa.func.length(sa.column("email")) <= 320
    )

    op.create_table(
        "verification_challenges",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column(
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
        ),
        sa.Column("channel", sa.Text(), nullable=False),
        sa.Column("code_hash", sa.Text(), nullable=False),
        sa.Column("expires_at", sa.DateTime(timezone=True), nullable=False),
        sa.Column("attempts", sa.Integer(), server_default="0", nullable=False),
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
            "user_id", sa.Uuid(), sa.ForeignKey("users.id", ondelete="CASCADE"), nullable=False
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
    for name in (
        "ck_users_email_max_length",
        "ck_users_phone_max_length",
        "ck_users_surname_max_length",
        "ck_users_first_name_max_length",
        "ck_users_surname_nonblank",
        "ck_users_first_name_nonblank",
        "uq_users_phone",
        "uq_users_email",
    ):
        op.drop_constraint(name, "users")
    for name in (
        "email_verified",
        "phone_verified",
        "password_hash",
        "email",
        "phone",
        "surname",
        "first_name",
    ):
        op.drop_column("users", name)
