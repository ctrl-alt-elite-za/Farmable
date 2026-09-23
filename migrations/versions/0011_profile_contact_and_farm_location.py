"""pending verified contact changes and farm location

Revision ID: 0011
Revises: 0010
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0011"
down_revision: str | None = "0010"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    # Additive only: nullable columns, no backfill, no existing row touched.
    op.add_column("auth_identities", sa.Column("pending_email", sa.Text(), nullable=True))
    op.add_column("auth_identities", sa.Column("pending_phone", sa.Text(), nullable=True))
    op.create_check_constraint(
        "ck_auth_identities_pending_email_max_length",
        "auth_identities",
        sa.func.length(sa.column("pending_email")) <= 320,
    )
    op.create_check_constraint(
        "ck_auth_identities_pending_phone_max_length",
        "auth_identities",
        sa.func.length(sa.column("pending_phone")) <= 32,
    )
    op.add_column("farms", sa.Column("latitude_tenths", sa.BigInteger(), nullable=True))
    op.add_column("farms", sa.Column("longitude_tenths", sa.BigInteger(), nullable=True))
    op.create_check_constraint(
        "ck_farms_lat", "farms", sa.column("latitude_tenths").between(-900, 900)
    )
    op.create_check_constraint(
        "ck_farms_lon", "farms", sa.column("longitude_tenths").between(-1800, 1799)
    )


def downgrade() -> None:
    op.drop_constraint("ck_farms_lon", "farms", type_="check")
    op.drop_constraint("ck_farms_lat", "farms", type_="check")
    op.drop_column("farms", "longitude_tenths")
    op.drop_column("farms", "latitude_tenths")
    op.drop_constraint("ck_auth_identities_pending_phone_max_length", "auth_identities", type_="check")
    op.drop_constraint("ck_auth_identities_pending_email_max_length", "auth_identities", type_="check")
    op.drop_column("auth_identities", "pending_phone")
    op.drop_column("auth_identities", "pending_email")
