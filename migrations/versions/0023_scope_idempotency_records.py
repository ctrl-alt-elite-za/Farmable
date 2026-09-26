"""scope idempotency records by caller

Revision ID: 0023
Revises: 0022
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0023"
down_revision: str | None = "0022"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None


def upgrade() -> None:
    op.add_column(
        "idempotency_records",
        sa.Column("scope", sa.Text(), nullable=False, server_default=""),
    )
    op.drop_constraint("idempotency_records_pkey", "idempotency_records", type_="primary")
    op.create_primary_key(
        "idempotency_records_pkey", "idempotency_records", ["route", "scope", "idempotency_key"]
    )
    op.create_check_constraint(
        "ck_idempotency_records_scope_max_length",
        "idempotency_records",
        sa.func.length(sa.column("scope")) <= 128,
    )


def downgrade() -> None:
    op.drop_constraint("ck_idempotency_records_scope_max_length", "idempotency_records")
    op.drop_constraint("idempotency_records_pkey", "idempotency_records", type_="primary")
    op.create_primary_key(
        "idempotency_records_pkey", "idempotency_records", ["route", "idempotency_key"]
    )
    op.drop_column("idempotency_records", "scope")
