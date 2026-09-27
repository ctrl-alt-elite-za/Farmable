"""pending verified contact changes and farm location

Revision ID: 0019
Revises: 0018
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0019"
down_revision: str | None = "0018"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Additive only: two new, empty tables. auth_identities and farms (whose
    # original migrations are immutable and pinned against the ORM by
    # test_auth_migration.py / test_farm_schema.py) are never altered.
    op.create_table(
        "pending_contact_changes",
        sa.Column(
            "user_id",
            sa.Uuid(),
            sa.ForeignKey("auth_identities.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("pending_email", sa.Text(), nullable=True),
        sa.Column("pending_phone", sa.Text(), nullable=True),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("pending_email")) <= 320,
            name="ck_pending_contact_changes_pending_email_max_length",
        ),
        sa.CheckConstraint(
            sa.func.length(sa.column("pending_phone")) <= 32,
            name="ck_pending_contact_changes_pending_phone_max_length",
        ),
    )
    op.create_table(
        "farm_locations",
        sa.Column(
            "farm_id", sa.Uuid(), sa.ForeignKey("farms.id", ondelete="CASCADE"), primary_key=True
        ),
        sa.Column("latitude_tenths", sa.BigInteger(), nullable=True),
        sa.Column("longitude_tenths", sa.BigInteger(), nullable=True),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.CheckConstraint(
            sa.column("latitude_tenths").between(-900, 900), name="ck_farm_locations_lat"
        ),
        sa.CheckConstraint(
            sa.column("longitude_tenths").between(-1800, 1799), name="ck_farm_locations_lon"
        ),
    )


def downgrade() -> None:
    # Deliberate and lossy: dropping these tables discards every stored
    # pending contact change and farm location. Identities, sessions and
    # farms are untouched.
    op.drop_table("farm_locations")
    op.drop_table("pending_contact_changes")
