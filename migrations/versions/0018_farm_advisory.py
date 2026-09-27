"""farm profiles and curated funding/procurement advisory catalog

Revision ID: 0018
Revises: 0017
"""

# Seed copy is kept close to the official source wording for reviewability.
# ruff: noqa: E501

import json
from collections.abc import Sequence
from datetime import date
from uuid import UUID

import sqlalchemy as sa
from alembic import op
from sqlalchemy import or_
from sqlalchemy.dialects import postgresql

revision: str = "0018"
down_revision: str | None = "0017"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

JSON_DOCUMENT = sa.JSON().with_variant(postgresql.JSONB(), "postgresql")
VERIFIED_ON = date(2026, 9, 27)


SEED_LISTS = {"farmer_types", "business_statuses", "crops", "strategy_steps"}


class SeedJson(sa.types.TypeDecorator):
    """JSONB that can also render as a SQL literal, for offline (--sql) migration runs."""

    impl = postgresql.JSONB
    cache_ok = True

    def process_literal_param(self, value, dialect):
        return "'" + json.dumps(value).replace("'", "''") + "'::jsonb"


def upgrade() -> None:
    op.create_table(
        "farm_profiles",
        sa.Column("farm_id", sa.Uuid(), nullable=False),
        sa.Column("owner_id", sa.Uuid(), nullable=False),
        sa.Column("province", sa.Text()),
        sa.Column("municipality", sa.Text()),
        sa.Column("farmer_type", sa.Text()),
        sa.Column("business_status", sa.Text()),
        sa.Column("farm_size_ha", sa.Numeric(14, 2)),
        sa.Column("annual_turnover_band", sa.Text()),
        sa.Column("crops", JSON_DOCUMENT, server_default="[]", nullable=False),
        sa.Column("goals", JSON_DOCUMENT, server_default="[]", nullable=False),
        sa.Column("equipment", JSON_DOCUMENT, server_default="[]", nullable=False),
        sa.Column(
            "updated_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("farm_id"),
        sa.ForeignKeyConstraint(
            ["farm_id", "owner_id"],
            ["farms.id", "farms.owner_id"],
            name="fk_farm_profiles_farm_owner",
            ondelete="CASCADE",
        ),
        sa.CheckConstraint(
            or_(sa.column("farm_size_ha").is_(None), sa.column("farm_size_ha") > 0),
            name="ck_farm_profiles_size_positive",
        ),
        sa.Index("ix_farm_profiles_owner", "owner_id"),
    )
    # create_table returns the Table; bulk_insert needs it, not the table's name.
    opportunities_table = op.create_table(
        "advisory_opportunities",
        sa.Column("id", sa.Uuid(), nullable=False),
        sa.Column("kind", sa.Text(), nullable=False),
        sa.Column("name", sa.Text(), nullable=False),
        sa.Column("provider", sa.Text(), nullable=False),
        sa.Column("summary", sa.Text(), nullable=False),
        sa.Column("province", sa.Text()),
        sa.Column("farmer_types", JSON_DOCUMENT, server_default="[]", nullable=False),
        sa.Column("business_statuses", JSON_DOCUMENT, server_default="[]", nullable=False),
        sa.Column("crops", JSON_DOCUMENT, server_default="[]", nullable=False),
        sa.Column("strategy_steps", JSON_DOCUMENT, server_default="[]", nullable=False),
        sa.Column("opens_on", sa.Date()),
        sa.Column("closes_on", sa.Date()),
        sa.Column("deadline_note", sa.Text(), nullable=False),
        sa.Column("source_url", sa.Text(), nullable=False),
        sa.Column("application_url", sa.Text()),
        sa.Column("verified_on", sa.Date(), nullable=False),
        sa.Column("active", sa.Boolean(), server_default=sa.true(), nullable=False),
        sa.Column(
            "created_at", sa.DateTime(timezone=True), server_default=sa.func.now(), nullable=False
        ),
        sa.PrimaryKeyConstraint("id"),
        sa.UniqueConstraint("kind", "provider", "name", name="uq_advisory_opportunity_name"),
        sa.CheckConstraint(
            sa.column("kind").in_(("funding", "procurement")), name="ck_advisory_opportunities_kind"
        ),
        sa.CheckConstraint(
            or_(
                sa.column("closes_on").is_(None),
                sa.column("opens_on").is_(None),
                sa.column("closes_on") >= sa.column("opens_on"),
            ),
            name="ck_advisory_opportunities_dates",
        ),
        sa.Index("ix_advisory_opportunities_kind_active", "kind", "active", "closes_on"),
    )
    opportunities = [
        {
            "id": UUID("00000000-0000-0000-0000-000000001801"),
            "kind": "funding",
            "name": "Comprehensive Agricultural Support Programme (CASP)",
            "provider": "South African Department of Agriculture",
            "summary": "Producer development support including infrastructure, inputs, training, mentorship and market access.",
            "province": "all",
            "farmer_types": [
                "subsistence",
                "smallholder",
                "black_commercial",
                "agrarian_reform",
                "farm_worker",
                "self_help_group",
            ],
            "business_statuses": [],
            "crops": ["vegetables", "cabbage", "tomatoes", "spinach", "mixed"],
            "strategy_steps": [
                "Prepare a farm business plan",
                "Document land access and production records",
                "Contact the nearest provincial or district agriculture office",
                "Ask for the current provincial application window",
            ],
            "opens_on": None,
            "closes_on": None,
            "deadline_note": "No fixed national closing date is published on the source page; confirm the current provincial window before applying.",
            "source_url": "https://www.gov.za/issues/land-and-agriculture",
            "application_url": "https://www.gov.za/issues/land-and-agriculture",
            "verified_on": VERIFIED_ON,
        },
        {
            "id": UUID("00000000-0000-0000-0000-000000001802"),
            "kind": "funding",
            "name": "MAFISA agricultural finance",
            "provider": "South African Department of Agriculture",
            "summary": "Production and small-equipment finance for qualifying smallholder agriculture, forestry and fisheries enterprises through accredited intermediaries.",
            "province": "all",
            "farmer_types": ["smallholder", "subsistence", "emerging"],
            "business_statuses": ["informal", "registered"],
            "crops": ["vegetables", "cabbage", "tomatoes", "spinach", "mixed"],
            "strategy_steps": [
                "Prepare a repayable production budget",
                "Collect identity and enterprise records",
                "Confirm the accredited intermediary",
                "Separate loan-funded inputs from grant requests",
            ],
            "opens_on": None,
            "closes_on": None,
            "deadline_note": "The official page describes eligibility and intermediary access, not a fixed national deadline; confirm availability with an accredited intermediary.",
            "source_url": "https://www.nda.gov.za/index.php/core-business/development-finance",
            "application_url": "https://www.nda.gov.za/index.php/core-business/development-finance",
            "verified_on": VERIFIED_ON,
        },
        {
            "id": UUID("00000000-0000-0000-0000-000000001803"),
            "kind": "procurement",
            "name": "eTenders agriculture supplier route",
            "provider": "National Treasury OCPO",
            "summary": "Official route for finding active public-sector tenders by category, province, organ of state and tender type.",
            "province": "all",
            "farmer_types": [],
            "business_statuses": ["registered"],
            "crops": ["vegetables", "cabbage", "tomatoes", "spinach", "mixed"],
            "strategy_steps": [
                "Register and keep Central Supplier Database details current",
                "Search active opportunities by food/agriculture category and province",
                "Download the official tender document",
                "Build a compliance pack before bidding",
                "Track clarification and closing dates from the tender document",
            ],
            "opens_on": None,
            "closes_on": None,
            "deadline_note": "Deadlines belong to each live tender and must be checked in the official tender document.",
            "source_url": "https://www.etenders.gov.za/Home/Opportunities",
            "application_url": "https://www.etenders.gov.za/Home/Opportunities",
            "verified_on": VERIFIED_ON,
        },
    ]
    # Same table, but the list columns use SeedJson so offline SQL can render them.
    seed_table = sa.table(
        "advisory_opportunities",
        *(
            sa.column(column.name, SeedJson() if column.name in SEED_LISTS else column.type)
            for column in opportunities_table.columns
        ),
    )
    op.bulk_insert(seed_table, opportunities)


def downgrade() -> None:
    op.drop_table("advisory_opportunities")
    op.drop_table("farm_profiles")
