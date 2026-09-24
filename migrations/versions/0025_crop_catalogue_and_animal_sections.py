"""crop catalogue, harvest windows and animal sections (#11)

Revision ID: 0025
Revises: 0024
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0025"
down_revision: str | None = "0024"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# This migration only installs identities. Calendar durations must come from a
# validated, sourced data import; demo durations belong in demo fixtures and
# must never silently become production harvest dates.
CROP_CATALOGUE = (
    ("cabbage", "Cabbage"),
    ("spinach", "Spinach"),
    ("tomato", "Tomato"),
    ("potato", "Potato"),
    ("onion", "Onion"),
    ("carrot", "Carrot"),
)


def upgrade() -> None:
    # Additive only: four new, empty-then-seeded tables. sections and
    # plantings (whose original migration 0003 is immutable and pinned
    # against the ORM by test_farm_schema.py) are never altered; kind and
    # the catalogue-restricted crop/harvest window (#11) live here instead,
    # the same companion-table pattern migration 0011 used for farm_locations.
    op.create_table(
        "section_kinds",
        sa.Column(
            "section_id",
            sa.Uuid(),
            sa.ForeignKey("sections.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("kind", sa.Text(), nullable=False, server_default="crop"),
        sa.CheckConstraint(sa.column("kind").in_(("crop", "animal")), name="ck_section_kinds_kind"),
    )
    crop_types = op.create_table(
        "crop_types",
        sa.Column("code", sa.Text(), primary_key=True),
        sa.Column("name", sa.Text(), nullable=False),
    )
    op.create_table(
        "crop_calendars",
        sa.Column(
            "crop_type_code",
            sa.Text(),
            sa.ForeignKey("crop_types.code", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("harvest_days_min", sa.BigInteger(), nullable=False),
        sa.Column("harvest_days_max", sa.BigInteger(), nullable=False),
        sa.CheckConstraint(
            sa.column("harvest_days_min") > 0, name="ck_crop_calendars_harvest_days_min_positive"
        ),
        sa.CheckConstraint(
            sa.column("harvest_days_max") >= sa.column("harvest_days_min"),
            name="ck_crop_calendars_harvest_days_order",
        ),
    )
    op.create_table(
        "planting_crops",
        sa.Column(
            "planting_id",
            sa.Uuid(),
            sa.ForeignKey("plantings.id", ondelete="CASCADE"),
            primary_key=True,
        ),
        sa.Column("crop_type_code", sa.Text(), nullable=False),
        sa.Column("harvest_from", sa.Date(), nullable=True),
        sa.Column("harvest_to", sa.Date(), nullable=True),
        sa.ForeignKeyConstraint(
            ("crop_type_code",), ("crop_types.code",), name="fk_planting_crops_crop_type"
        ),
    )
    op.bulk_insert(crop_types, [{"code": code, "name": name} for code, name in CROP_CATALOGUE])


def downgrade() -> None:
    op.drop_table("planting_crops")
    op.drop_table("crop_calendars")
    op.drop_table("crop_types")
    op.drop_table("section_kinds")
