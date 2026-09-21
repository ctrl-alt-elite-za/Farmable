from datetime import date, datetime
from decimal import Decimal
from typing import Annotated, Any
from uuid import UUID, uuid4

from geoalchemy2 import Geometry
from geoalchemy2.elements import WKBElement
from sqlalchemy import (
    JSON,
    BigInteger,
    Boolean,
    CheckConstraint,
    Date,
    DateTime,
    ForeignKey,
    Identity,
    Index,
    Integer,
    Numeric,
    Text,
    UniqueConstraint,
    Uuid,
    column,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

# Spinach is sold by bunch or kilogram, so only these crops get a per-plant formula (#16).
WEIGHED_CROPS = ("cabbage", "tomato")
SYNC_STATES = ("pending", "synced", "conflict")
TASK_STATUSES = ("pending", "in_progress", "done", "cancelled")
FINANCIAL_TYPES = ("expense", "income")
PLAN_STATUSES = ("saved", "approved", "rejected")


class Base(DeclarativeBase):
    """Declarative base for Farmable's ORM models."""


# Migration 0002 must declare these tables identically; tests/test_vision_schema.py compares them.
class DetectorModel(Base):
    __tablename__ = "detector_models"
    __table_args__ = (
        UniqueConstraint("version", name="uq_detector_models_version"),
        CheckConstraint(
            column("artifact_sha256").regexp_match("^[0-9a-f]{64}$"),
            name="ck_detector_models_artifact_sha256_hex",
        ),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    version: Mapped[str] = mapped_column(Text)
    artifact_uri: Mapped[str] = mapped_column(Text)
    artifact_sha256: Mapped[str] = mapped_column(Text)
    metrics: Mapped[dict[str, Any]] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WeightFormula(Base):
    __tablename__ = "weight_formulas"
    __table_args__ = (
        UniqueConstraint("crop", "version", name="uq_weight_formulas_crop_version"),
        CheckConstraint(column("crop").in_(WEIGHED_CROPS), name="ck_weight_formulas_weighed_crop"),
    )

    id: Mapped[int] = mapped_column(BigInteger, Identity(), primary_key=True)
    crop: Mapped[str] = mapped_column(Text)
    version: Mapped[str] = mapped_column(Text)
    formula: Mapped[dict[str, Any]] = mapped_column(JSON)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class User(Base):
    __tablename__ = "users"

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Farm(Base):
    __tablename__ = "farms"
    __table_args__ = (
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name="ck_farms_sync_state"),
        Index("ix_farms_owner_id", "owner_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Section(Base):
    __tablename__ = "sections"
    __table_args__ = (
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name="ck_sections_sync_state"),
        Index("ix_sections_farm_id", "farm_id"),
        Index("ix_sections_owner_id", "owner_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(Text)
    boundary: Mapped[dict[str, Any] | None] = mapped_column(JSON)
    area_m2: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Planting(Base):
    __tablename__ = "plantings"
    __table_args__ = (
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name="ck_plantings_sync_state"),
        Index("ix_plantings_farm_id", "farm_id"),
        Index("ix_plantings_owner_id", "owner_id"),
        Index("ix_plantings_section_id", "section_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    section_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("sections.id", ondelete="CASCADE"))
    crop: Mapped[str] = mapped_column(Text)
    planted_on: Mapped[date | None] = mapped_column(Date)
    is_current: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Media(Base):
    __tablename__ = "media"
    __table_args__ = (
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name="ck_media_sync_state"),
        UniqueConstraint("owner_id", "local_id", name="uq_media_owner_local_id"),
        Index("ix_media_farm_id", "farm_id"),
        Index("ix_media_owner_id", "owner_id"),
        Index("ix_media_section_id", "section_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    section_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("sections.id", ondelete="SET NULL")
    )
    local_id: Mapped[str] = mapped_column(Text)
    object_key: Mapped[str | None] = mapped_column(Text)
    media_type: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Observation(Base):
    __tablename__ = "observations"
    __table_args__ = (
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name="ck_observations_sync_state"),
        Index("ix_observations_farm_id", "farm_id"),
        Index("ix_observations_owner_id", "owner_id"),
        Index("ix_observations_section_id", "section_id"),
        Index("ix_observations_local_media_id", "local_media_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    section_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("sections.id", ondelete="CASCADE"))
    type: Mapped[str] = mapped_column(Text)
    note: Mapped[str] = mapped_column(Text)
    health_status: Mapped[str | None] = mapped_column(Text)
    action_taken: Mapped[str | None] = mapped_column(Text)
    local_media_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("media.id", ondelete="SET NULL")
    )
    created_by_voice: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class FarmTask(Base):
    __tablename__ = "farm_tasks"
    __table_args__ = (
        CheckConstraint(column("status").in_(TASK_STATUSES), name="ck_farm_tasks_status"),
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name="ck_farm_tasks_sync_state"),
        Index("ix_farm_tasks_farm_id", "farm_id"),
        Index("ix_farm_tasks_owner_id", "owner_id"),
        Index("ix_farm_tasks_section_id", "section_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    section_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("sections.id", ondelete="CASCADE"))
    title: Mapped[str] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)
    due_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    expected_cost_cents: Mapped[int | None] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class FinancialRecord(Base):
    __tablename__ = "financial_records"
    __table_args__ = (
        CheckConstraint(column("type").in_(FINANCIAL_TYPES), name="ck_financial_records_type"),
        CheckConstraint(
            column("amount_cents") >= 0, name="ck_financial_records_amount_nonnegative"
        ),
        CheckConstraint(
            column("sync_state").in_(SYNC_STATES), name="ck_financial_records_sync_state"
        ),
        Index("ix_financial_records_farm_id", "farm_id"),
        Index("ix_financial_records_owner_id", "owner_id"),
        Index("ix_financial_records_section_id", "section_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    section_id: Mapped[UUID | None] = mapped_column(
        Uuid, ForeignKey("sections.id", ondelete="SET NULL")
    )
    type: Mapped[str] = mapped_column(Text)
    category: Mapped[str] = mapped_column(Text)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    date: Mapped[date] = mapped_column(Date)
    note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SavedPlan(Base):
    __tablename__ = "saved_plans"
    __table_args__ = (
        CheckConstraint(column("status").in_(PLAN_STATUSES), name="ck_saved_plans_status"),
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name="ck_saved_plans_sync_state"),
        Index("ix_saved_plans_farm_id", "farm_id"),
        Index("ix_saved_plans_owner_id", "owner_id"),
        Index("ix_saved_plans_section_id", "section_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    section_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("sections.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(Text, default="saved", server_default="saved")
    plan: Mapped[dict[str, Any]] = mapped_column(JSON)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(Integer, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SyncMutation(Base):
    __tablename__ = "sync_mutations"
    __table_args__ = (
        UniqueConstraint("mutation_id", name="uq_sync_mutations_mutation_id"),
        Index("ix_sync_mutations_farm_id", "farm_id"),
        Index("ix_sync_mutations_owner_id", "owner_id"),
        Index("ix_sync_mutations_record_id", "record_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    mutation_id: Mapped[UUID] = mapped_column(Uuid)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    operation: Mapped[str] = mapped_column(Text)
    record_type: Mapped[str] = mapped_column(Text)
    record_id: Mapped[UUID] = mapped_column(Uuid)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SyncChange(Base):
    __tablename__ = "sync_changes"
    __table_args__ = (
        Index("ix_sync_changes_farm_id", "farm_id"),
        Index("ix_sync_changes_owner_id", "owner_id"),
        Index("ix_sync_changes_mutation_id", "mutation_id"),
        Index("ix_sync_changes_record_id", "record_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("farms.id", ondelete="CASCADE"))
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    mutation_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("sync_mutations.id", ondelete="CASCADE")
    )
    record_type: Mapped[str] = mapped_column(Text)
    record_id: Mapped[UUID] = mapped_column(Uuid)
    operation: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(Integer)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# Reusable ORM field annotations for future models (#8), not feature tables.
Point = Annotated[WKBElement, mapped_column(Geometry("POINT", srid=4326))]
Shape = Annotated[WKBElement, mapped_column(Geometry("MULTIPOLYGON", srid=4326))]
