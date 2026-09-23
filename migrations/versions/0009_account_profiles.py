"""account language preference profiles

Revision ID: 0009
Revises: 0008
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0009"
down_revision: str | None = "0008"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

ACCOUNT_LANGUAGES = ("en", "af", "nso", "st", "xh", "zu")


def upgrade() -> None:
    # Additive only: one new, empty table. Existing users, auth_identities and
    # farm ownership rows are never altered, backfilled or re-indexed. The
    # foreign key still needs a short metadata lock on auth_identities;
    # migrations/env.py configures bounded lock and statement waits.
    op.create_table(
        "account_profiles",
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("auth_identities.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("preferred_language", sa.Text(), server_default="en", nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.column("preferred_language").in_(ACCOUNT_LANGUAGES),
            name="ck_account_profiles_preferred_language",
        ),
    )


def downgrade() -> None:
    # Deliberate and lossy: dropping the table discards every stored language
    # preference. Identities, sessions, farms and ownership are untouched, so
    # the application falls back to the "en" default after a downgrade.
    op.drop_table("account_profiles")
