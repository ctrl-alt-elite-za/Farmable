"""Traceable reference prices, calendars and costs.

Revision ID: 0010
Revises: 0009
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op
from sqlalchemy.dialects import postgresql

revision: str = "0010"
down_revision: str | None = "0009"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

CROPS = (
    "butternut",
    "cabbage",
    "carrots",
    "green_beans",
    "onions",
    "potatoes",
    "spinach",
    "tomatoes",
)


def upgrade() -> None:
    op.create_table(
        "reference_imports",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("dataset_kind", sa.Text(), nullable=False),
        sa.Column("dataset_key", sa.Text(), nullable=False),
        sa.Column("source_file", sa.Text(), nullable=False),
        sa.Column("source_sha256", sa.Text(), nullable=False),
        sa.Column("payload_sha256", sa.Text(), nullable=False),
        sa.Column("parser_version", sa.BigInteger(), nullable=False),
        sa.Column("row_count", sa.BigInteger(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("dataset_kind", "dataset_key", name="uq_reference_imports_dataset"),
        sa.CheckConstraint(
            sa.column("source_sha256").regexp_match("^[0-9a-f]{64}$"),
            name="ck_reference_imports_source_sha256_hex",
        ),
        sa.CheckConstraint(
            sa.column("payload_sha256").regexp_match("^[0-9a-f]{64}$"),
            name="ck_reference_imports_payload_sha256_hex",
        ),
        sa.CheckConstraint(
            sa.column("parser_version") > 0, name="ck_reference_imports_parser_positive"
        ),
        sa.CheckConstraint(sa.column("row_count") > 0, name="ck_reference_imports_rows_positive"),
    )
    op.create_table(
        "reference_market_prices",
        sa.Column("import_id", sa.Uuid(), nullable=False),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("market", sa.Text(), nullable=False),
        sa.Column("observation_month", sa.Date(), nullable=False),
        sa.Column("available_on", sa.Date(), nullable=False),
        sa.Column("price_rand_per_kg", sa.Numeric(14, 4), nullable=False),
        sa.Column("availability_kind", sa.Text(), nullable=False),
        sa.PrimaryKeyConstraint("import_id", "crop", "market", "observation_month"),
        sa.ForeignKeyConstraint(["import_id"], ["reference_imports.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "crop", "market", "observation_month", name="uq_reference_market_prices_natural"
        ),
        sa.CheckConstraint(sa.column("crop").in_(CROPS), name="ck_reference_prices_crop"),
        sa.CheckConstraint(sa.column("price_rand_per_kg") > 0, name="ck_reference_prices_positive"),
        sa.CheckConstraint(
            sa.column("availability_kind").in_(("publication", "analytical_next_month")),
            name="ck_reference_prices_availability_kind",
        ),
    )
    op.create_table(
        "reference_crop_calendars",
        sa.Column("import_id", sa.Uuid(), nullable=False),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("region", sa.Text(), nullable=False),
        sa.Column("effective_on", sa.Date(), nullable=False),
        sa.Column("available_on", sa.Date(), nullable=False),
        sa.Column("revision", sa.BigInteger(), nullable=False),
        sa.Column(
            "planting_months",
            sa.JSON().with_variant(postgresql.JSONB(), "postgresql"),
            nullable=False,
        ),
        sa.Column("harvest_offset_months", sa.BigInteger(), nullable=False),
        sa.Column("yield_kg_per_ha", sa.Numeric(14, 4), nullable=False),
        sa.Column("assumption_kind", sa.Text(), nullable=False),
        sa.PrimaryKeyConstraint("import_id", "crop", "region", "effective_on", "revision"),
        sa.ForeignKeyConstraint(["import_id"], ["reference_imports.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "crop", "region", "effective_on", "revision", name="uq_reference_calendars_natural"
        ),
        sa.CheckConstraint(sa.column("crop").in_(CROPS), name="ck_reference_calendars_crop"),
        sa.CheckConstraint(
            sa.column("harvest_offset_months") > 0, name="ck_reference_calendar_offset"
        ),
        sa.CheckConstraint(sa.column("yield_kg_per_ha") > 0, name="ck_reference_calendar_yield"),
    )
    op.create_table(
        "reference_crop_costs",
        sa.Column("import_id", sa.Uuid(), nullable=False),
        sa.Column("crop", sa.Text(), nullable=False),
        sa.Column("region", sa.Text(), nullable=False),
        sa.Column("effective_on", sa.Date(), nullable=False),
        sa.Column("available_on", sa.Date(), nullable=False),
        sa.Column("revision", sa.BigInteger(), nullable=False),
        sa.Column("basis_year", sa.BigInteger(), nullable=False),
        sa.Column("cost_rand_per_ha", sa.Numeric(14, 4), nullable=False),
        sa.Column("marketing_rate", sa.Numeric(8, 6), nullable=False),
        sa.Column("vat_basis", sa.Text(), nullable=False),
        sa.PrimaryKeyConstraint("import_id", "crop", "region", "effective_on", "revision"),
        sa.ForeignKeyConstraint(["import_id"], ["reference_imports.id"], ondelete="CASCADE"),
        sa.UniqueConstraint(
            "crop", "region", "effective_on", "revision", name="uq_reference_costs_natural"
        ),
        sa.CheckConstraint(sa.column("crop").in_(CROPS), name="ck_reference_costs_crop"),
        sa.CheckConstraint(
            sa.column("cost_rand_per_ha") >= 0, name="ck_reference_cost_nonnegative"
        ),
        sa.CheckConstraint(
            sa.column("marketing_rate").between(0, sa.literal(0.999999)),
            name="ck_reference_cost_marketing_rate",
        ),
    )


def downgrade() -> None:
    op.drop_table("reference_crop_costs")
    op.drop_table("reference_crop_calendars")
    op.drop_table("reference_market_prices")
    op.drop_table("reference_imports")
