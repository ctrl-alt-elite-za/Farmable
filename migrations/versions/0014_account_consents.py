"""versioned account consents

Revision ID: 0014
Revises: 0013
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0014"
down_revision: str | None = "0013"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.create_table(
        "account_consents",
        sa.Column("id", sa.Uuid(), primary_key=True),
        sa.Column("user_id", sa.Uuid(), sa.ForeignKey("auth_identities.id", ondelete="CASCADE"), nullable=False),
        sa.Column("consent_type", sa.Text(), nullable=False),
        sa.Column("version", sa.Text(), nullable=False),
        sa.Column("granted_at", sa.DateTime(timezone=True)),
        sa.Column("withdrawn_at", sa.DateTime(timezone=True)),
        sa.Column("source", sa.Text(), nullable=False, server_default="api"),
        sa.UniqueConstraint("user_id", "consent_type", "version", name="uq_account_consents_version"),
        sa.CheckConstraint("length(trim(consent_type)) > 0", name="ck_account_consents_consent_type_nonblank"),
        sa.CheckConstraint("length(consent_type) <= 80", name="ck_account_consents_consent_type_max_length"),
        sa.CheckConstraint("length(version) <= 40", name="ck_account_consents_version_max_length"),
        sa.CheckConstraint("length(source) <= 40", name="ck_account_consents_source_max_length"),
    )
    op.create_index("ix_account_consents_user_id", "account_consents", ["user_id"])


def downgrade() -> None:
    op.drop_index("ix_account_consents_user_id", table_name="account_consents")
    op.drop_table("account_consents")
