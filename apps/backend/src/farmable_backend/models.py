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
    ForeignKeyConstraint,
    Identity,
    Index,
    Integer,
    LargeBinary,
    Numeric,
    Text,
    UniqueConstraint,
    Uuid,
    column,
    func,
)
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

from farmable_backend.photo_policy import MAX_CLAIMS

# Spinach is sold by bunch or kilogram, so only these crops get a per-plant formula (#16).
WEIGHED_CROPS = ("cabbage", "tomato")
SYNC_STATES = ("pending", "synced", "conflict")
TASK_STATUSES = ("pending", "in_progress", "done", "cancelled")
FINANCIAL_TYPES = ("expense", "income")
PLAN_STATUSES = ("saved", "approved", "rejected")
ACCOUNT_LANGUAGES = ("en", "af", "nso", "st", "xh", "zu")
DEFAULT_ACCOUNT_LANGUAGE = "en"

JSON_DOCUMENT = JSON().with_variant(JSONB(), "postgresql")
CHANGE_CURSOR = BigInteger().with_variant(Integer(), "sqlite")


def _owned_constraints(table: str) -> tuple[CheckConstraint, ...]:
    return (
        CheckConstraint(column("version") > 0, name=f"ck_{table}_version_positive"),
        CheckConstraint(column("sync_state").in_(SYNC_STATES), name=f"ck_{table}_sync_state"),
        _max_length("sync_state", table, 20),
    )


def _farm_owner_fk(table: str) -> ForeignKeyConstraint:
    return ForeignKeyConstraint(
        ("farm_id", "owner_id"),
        ("farms.id", "farms.owner_id"),
        name=f"fk_{table}_farm_owner",
        ondelete="CASCADE",
    )


def _section_owner_fk(table: str) -> ForeignKeyConstraint:
    return ForeignKeyConstraint(
        ("section_id", "farm_id", "owner_id"),
        ("sections.id", "sections.farm_id", "sections.owner_id"),
        name=f"fk_{table}_section_farm_owner",
        deferrable=True,
        initially="DEFERRED",
    )


def _nonblank(name: str, table: str) -> CheckConstraint:
    return CheckConstraint(
        func.length(func.trim(column(name))) > 0,
        name=f"ck_{table}_{name}_nonblank",
    )


def _max_length(name: str, table: str, maximum: int) -> CheckConstraint:
    return CheckConstraint(
        func.length(column(name)) <= maximum,
        name=f"ck_{table}_{name}_max_length",
    )


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


class AuthIdentity(Base):
    """Optional credentials for an existing ownership identity; no legacy backfill."""

    __tablename__ = "auth_identities"
    __table_args__ = (
        UniqueConstraint("email", name="uq_auth_identities_email"),
        UniqueConstraint("phone", name="uq_auth_identities_phone"),
        _nonblank("first_name", "auth_identities"),
        _nonblank("surname", "auth_identities"),
        _max_length("first_name", "auth_identities", 100),
        _max_length("surname", "auth_identities", 100),
        _max_length("phone", "auth_identities", 32),
        _max_length("email", "auth_identities", 320),
    )

    id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    first_name: Mapped[str] = mapped_column(Text)
    surname: Mapped[str] = mapped_column(Text)
    phone: Mapped[str] = mapped_column(Text)
    email: Mapped[str] = mapped_column(Text)
    password_hash: Mapped[str] = mapped_column(Text)
    phone_verified: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    email_verified: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class VerificationChallenge(Base):
    __tablename__ = "verification_challenges"
    __table_args__ = (
        CheckConstraint(column("channel").in_(("phone", "email")), name="ck_verification_channel"),
        Index("ix_verification_challenges_user_channel", "user_id", "channel", "expires_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("auth_identities.id", ondelete="CASCADE")
    )
    channel: Mapped[str] = mapped_column(Text)
    code_hash: Mapped[str] = mapped_column(Text)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempts: Mapped[int] = mapped_column(BigInteger, default=0, server_default="0")
    consumed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AuthSession(Base):
    __tablename__ = "auth_sessions"
    __table_args__ = (
        Index("ix_auth_sessions_access_token_hash", "access_token_hash", unique=True),
        Index("ix_auth_sessions_refresh_token_hash", "refresh_token_hash", unique=True),
        Index("ix_auth_sessions_user_active", "user_id", "revoked_at", "expires_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("auth_identities.id", ondelete="CASCADE")
    )
    access_token_hash: Mapped[str] = mapped_column(Text)
    refresh_token_hash: Mapped[str] = mapped_column(Text)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class AccountProfile(Base):
    """Account preferences.

    A separate table, not new columns on auth_identities: migration 0004 is
    already deployed and immutable, and tests/test_auth_migration.py asserts
    that its CREATE TABLE text still matches the ORM exactly.
    """

    __tablename__ = "account_profiles"
    __table_args__ = (
        CheckConstraint(
            column("preferred_language").in_(ACCOUNT_LANGUAGES),
            name="ck_account_profiles_preferred_language",
        ),
    )

    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("auth_identities.id", ondelete="CASCADE"), primary_key=True
    )
    preferred_language: Mapped[str] = mapped_column(
        Text, default=DEFAULT_ACCOUNT_LANGUAGE, server_default=DEFAULT_ACCOUNT_LANGUAGE
    )
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Consent(Base):
    """Versioned, auditable consent state for POPIA/account operations."""

    __tablename__ = "account_consents"
    __table_args__ = (
        UniqueConstraint("user_id", "consent_type", "version", name="uq_account_consents_version"),
        _nonblank("consent_type", "account_consents"),
        _max_length("consent_type", "account_consents", 80),
        _max_length("version", "account_consents", 40),
        _max_length("source", "account_consents", 40),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("auth_identities.id", ondelete="CASCADE"), index=True
    )
    consent_type: Mapped[str] = mapped_column(Text)
    version: Mapped[str] = mapped_column(Text)
    granted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    withdrawn_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    source: Mapped[str] = mapped_column(Text, default="api", server_default="api")


class PendingContactChange(Base):
    """A verified account's requested-but-unconfirmed email/phone change.

    A separate table, not new columns on auth_identities, for the same reason
    as AccountProfile: migration 0004 is immutable and pinned against the
    current ORM by tests/test_auth_migration.py. Never applied to
    auth_identities.email/phone until the matching VerificationChallenge is
    consumed via AccountService.confirm_contact_change.
    """

    __tablename__ = "pending_contact_changes"
    __table_args__ = (
        _max_length("pending_email", "pending_contact_changes", 320),
        _max_length("pending_phone", "pending_contact_changes", 32),
    )

    user_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("auth_identities.id", ondelete="CASCADE"), primary_key=True
    )
    pending_email: Mapped[str | None] = mapped_column(Text)
    pending_phone: Mapped[str | None] = mapped_column(Text)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class FarmLocation(Base):
    """A farm's optional coordinates, rounded to tenths of a degree like
    WeatherJob's existing lat/lon representation, for consistency.

    A separate table, not new columns on farms, for the same reason as
    AccountProfile/PendingContactChange: migration 0003 is immutable and
    pinned against the current ORM by tests/test_farm_schema.py.
    """

    __tablename__ = "farm_locations"
    __table_args__ = (
        CheckConstraint(column("latitude_tenths").between(-900, 900), name="ck_farm_locations_lat"),
        CheckConstraint(
            column("longitude_tenths").between(-1800, 1799), name="ck_farm_locations_lon"
        ),
    )

    farm_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("farms.id", ondelete="CASCADE"), primary_key=True
    )
    latitude_tenths: Mapped[int | None] = mapped_column(BigInteger)
    longitude_tenths: Mapped[int | None] = mapped_column(BigInteger)
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class Farm(Base):
    __tablename__ = "farms"
    __table_args__ = (
        *_owned_constraints("farms"),
        _nonblank("name", "farms"),
        _max_length("name", "farms", 200),
        UniqueConstraint("id", "owner_id", name="uq_farms_id_owner_id"),
        Index("ix_farms_owner_active", "owner_id", "deleted_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    name: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Section(Base):
    __tablename__ = "sections"
    __table_args__ = (
        *_owned_constraints("sections"),
        _farm_owner_fk("sections"),
        _nonblank("name", "sections"),
        _max_length("name", "sections", 200),
        CheckConstraint(
            (column("area_m2").is_(None)) | (column("area_m2") > 0),
            name="ck_sections_area_positive",
        ),
        UniqueConstraint("id", "farm_id", "owner_id", name="uq_sections_id_farm_owner"),
        Index("ix_sections_owner_farm_active", "owner_id", "farm_id", "deleted_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    name: Mapped[str] = mapped_column(Text)
    boundary: Mapped[dict[str, Any] | None] = mapped_column(JSON_DOCUMENT)
    area_m2: Mapped[Decimal | None] = mapped_column(Numeric(14, 2))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Planting(Base):
    __tablename__ = "plantings"
    __table_args__ = (
        *_owned_constraints("plantings"),
        _farm_owner_fk("plantings"),
        _section_owner_fk("plantings"),
        _nonblank("crop", "plantings"),
        _max_length("crop", "plantings", 100),
        Index("ix_plantings_owner_farm_active", "owner_id", "farm_id", "deleted_at"),
        Index(
            "uq_plantings_current_section",
            "section_id",
            unique=True,
            postgresql_where=column("is_current").is_(True) & column("deleted_at").is_(None),
            sqlite_where=column("is_current").is_(True) & column("deleted_at").is_(None),
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    section_id: Mapped[UUID] = mapped_column(Uuid)
    crop: Mapped[str] = mapped_column(Text)
    planted_on: Mapped[date | None] = mapped_column(Date)
    is_current: Mapped[bool] = mapped_column(Boolean, default=True, server_default="true")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Media(Base):
    __tablename__ = "media"
    __table_args__ = (
        *_owned_constraints("media"),
        _farm_owner_fk("media"),
        _section_owner_fk("media"),
        _nonblank("local_id", "media"),
        _nonblank("media_type", "media"),
        _max_length("local_id", "media", 255),
        _max_length("object_key", "media", 1024),
        _max_length("media_type", "media", 100),
        CheckConstraint(
            (column("object_key").is_(None)) | (func.length(func.trim(column("object_key"))) > 0),
            name="ck_media_object_key_nonblank",
        ),
        UniqueConstraint("id", "farm_id", "owner_id", name="uq_media_id_farm_owner"),
        UniqueConstraint("owner_id", "local_id", name="uq_media_owner_local_id"),
        Index("ix_media_owner_farm_active", "owner_id", "farm_id", "deleted_at"),
        Index("ix_media_section_id", "section_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    section_id: Mapped[UUID | None] = mapped_column(Uuid)
    local_id: Mapped[str] = mapped_column(Text)
    object_key: Mapped[str | None] = mapped_column(Text)
    media_type: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class Observation(Base):
    __tablename__ = "observations"
    __table_args__ = (
        *_owned_constraints("observations"),
        _farm_owner_fk("observations"),
        _section_owner_fk("observations"),
        ForeignKeyConstraint(
            ("local_media_id", "farm_id", "owner_id"),
            ("media.id", "media.farm_id", "media.owner_id"),
            name="fk_observations_media_farm_owner",
            deferrable=True,
            initially="DEFERRED",
        ),
        _nonblank("type", "observations"),
        _nonblank("note", "observations"),
        _max_length("type", "observations", 100),
        _max_length("note", "observations", 10000),
        _max_length("health_status", "observations", 100),
        _max_length("action_taken", "observations", 10000),
        Index("ix_observations_owner_farm_active", "owner_id", "farm_id", "deleted_at"),
        Index(
            "ix_observations_section_created",
            "owner_id",
            "farm_id",
            "section_id",
            "created_at",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    section_id: Mapped[UUID] = mapped_column(Uuid)
    type: Mapped[str] = mapped_column(Text)
    note: Mapped[str] = mapped_column(Text)
    health_status: Mapped[str | None] = mapped_column(Text)
    action_taken: Mapped[str | None] = mapped_column(Text)
    local_media_id: Mapped[UUID | None] = mapped_column(Uuid)
    created_by_voice: Mapped[bool] = mapped_column(Boolean, default=False, server_default="false")
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class FarmTask(Base):
    __tablename__ = "farm_tasks"
    __table_args__ = (
        *_owned_constraints("farm_tasks"),
        _farm_owner_fk("farm_tasks"),
        _section_owner_fk("farm_tasks"),
        CheckConstraint(column("status").in_(TASK_STATUSES), name="ck_farm_tasks_status"),
        CheckConstraint(
            (column("expected_cost_cents").is_(None)) | (column("expected_cost_cents") >= 0),
            name="ck_farm_tasks_expected_cost_nonnegative",
        ),
        _nonblank("title", "farm_tasks"),
        _max_length("title", "farm_tasks", 200),
        _max_length("description", "farm_tasks", 10000),
        _max_length("status", "farm_tasks", 20),
        Index("ix_farm_tasks_owner_farm_active", "owner_id", "farm_id", "deleted_at"),
        Index(
            "ix_farm_tasks_section_due",
            "owner_id",
            "farm_id",
            "section_id",
            "due_date",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    section_id: Mapped[UUID] = mapped_column(Uuid)
    title: Mapped[str] = mapped_column(Text)
    description: Mapped[str | None] = mapped_column(Text)
    due_date: Mapped[date] = mapped_column(Date)
    status: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    expected_cost_cents: Mapped[int | None] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class FinancialRecord(Base):
    __tablename__ = "financial_records"
    __table_args__ = (
        *_owned_constraints("financial_records"),
        _farm_owner_fk("financial_records"),
        _section_owner_fk("financial_records"),
        CheckConstraint(column("type").in_(FINANCIAL_TYPES), name="ck_financial_records_type"),
        CheckConstraint(
            column("amount_cents") >= 0, name="ck_financial_records_amount_nonnegative"
        ),
        _nonblank("category", "financial_records"),
        _max_length("type", "financial_records", 20),
        _max_length("category", "financial_records", 100),
        _max_length("note", "financial_records", 10000),
        Index("ix_financial_records_owner_farm_active", "owner_id", "farm_id", "deleted_at"),
        Index(
            "ix_financial_records_section_date",
            "owner_id",
            "farm_id",
            "section_id",
            "date",
        ),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    section_id: Mapped[UUID | None] = mapped_column(Uuid)
    type: Mapped[str] = mapped_column(Text)
    category: Mapped[str] = mapped_column(Text)
    amount_cents: Mapped[int] = mapped_column(BigInteger)
    date: Mapped[date] = mapped_column(Date)
    note: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SavedPlan(Base):
    __tablename__ = "saved_plans"
    __table_args__ = (
        *_owned_constraints("saved_plans"),
        _farm_owner_fk("saved_plans"),
        _section_owner_fk("saved_plans"),
        CheckConstraint(column("status").in_(PLAN_STATUSES), name="ck_saved_plans_status"),
        _max_length("status", "saved_plans", 20),
        Index("ix_saved_plans_owner_farm_active", "owner_id", "farm_id", "deleted_at"),
        Index("ix_saved_plans_section_id", "section_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    section_id: Mapped[UUID] = mapped_column(Uuid)
    status: Mapped[str] = mapped_column(Text, default="saved", server_default="saved")
    plan: Mapped[dict[str, Any]] = mapped_column(JSON_DOCUMENT)
    approved_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )
    version: Mapped[int] = mapped_column(BigInteger, default=1, server_default="1")
    sync_state: Mapped[str] = mapped_column(Text, default="pending", server_default="pending")
    deleted_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class SyncMutation(Base):
    __tablename__ = "sync_mutations"
    __table_args__ = (
        _farm_owner_fk("sync_mutations"),
        CheckConstraint(
            column("request_fingerprint").regexp_match("^[0-9a-f]{64}$"),
            name="ck_sync_mutations_request_fingerprint_hex",
        ),
        _nonblank("operation", "sync_mutations"),
        _nonblank("record_type", "sync_mutations"),
        _max_length("operation", "sync_mutations", 20),
        _max_length("record_type", "sync_mutations", 100),
        UniqueConstraint("mutation_id", name="uq_sync_mutations_mutation_id"),
        UniqueConstraint("id", "farm_id", "owner_id", name="uq_sync_mutations_id_farm_owner"),
        Index("ix_sync_mutations_owner_farm", "owner_id", "farm_id"),
        Index("ix_sync_mutations_record", "record_type", "record_id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    mutation_id: Mapped[UUID] = mapped_column(Uuid)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    operation: Mapped[str] = mapped_column(Text)
    record_type: Mapped[str] = mapped_column(Text)
    record_id: Mapped[UUID] = mapped_column(Uuid)
    request_fingerprint: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class SyncChange(Base):
    __tablename__ = "sync_changes"
    __table_args__ = (
        _farm_owner_fk("sync_changes"),
        ForeignKeyConstraint(
            ("mutation_id", "farm_id", "owner_id"),
            ("sync_mutations.id", "sync_mutations.farm_id", "sync_mutations.owner_id"),
            name="fk_sync_changes_mutation_farm_owner",
            ondelete="CASCADE",
        ),
        CheckConstraint(column("version") > 0, name="ck_sync_changes_version_positive"),
        _nonblank("operation", "sync_changes"),
        _nonblank("record_type", "sync_changes"),
        _max_length("operation", "sync_changes", 20),
        _max_length("record_type", "sync_changes", 100),
        Index("ix_sync_changes_owner_farm_cursor", "owner_id", "farm_id", "id"),
        Index("ix_sync_changes_mutation_id", "mutation_id"),
        Index("ix_sync_changes_record", "record_type", "record_id"),
    )

    id: Mapped[int] = mapped_column(CHANGE_CURSOR, Identity(), primary_key=True)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    mutation_id: Mapped[UUID] = mapped_column(Uuid)
    record_type: Mapped[str] = mapped_column(Text)
    record_id: Mapped[UUID] = mapped_column(Uuid)
    operation: Mapped[str] = mapped_column(Text)
    version: Mapped[int] = mapped_column(BigInteger)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PhotoUpload(Base):
    """Immutable logical media mutation; state is not the generic sync_state."""

    __tablename__ = "photo_uploads"
    __table_args__ = (
        _farm_owner_fk("photo_uploads"),
        _section_owner_fk("photo_uploads"),
        ForeignKeyConstraint(
            ("mutation_row_id", "farm_id", "owner_id"),
            ("sync_mutations.id", "sync_mutations.farm_id", "sync_mutations.owner_id"),
            name="fk_photo_uploads_mutation_scope",
        ),
        UniqueConstraint("owner_id", "local_media_id", name="uq_photo_uploads_local"),
        UniqueConstraint("mutation_row_id", name="uq_photo_uploads_mutation"),
        UniqueConstraint("media_id", name="uq_photo_uploads_media"),
        CheckConstraint(
            column("content_type").in_(("image/jpeg", "image/png")), name="ck_photo_uploads_type"
        ),
        CheckConstraint(column("byte_length").between(1, 5_000_000), name="ck_photo_uploads_size"),
        CheckConstraint(
            column("state").in_(
                ("awaiting_upload", "queued", "processing", "ready", "failed", "expired")
            ),
            name="ck_photo_uploads_state",
        ),
        CheckConstraint(column("sequence") > 0, name="ck_photo_uploads_sequence"),
        Index("ix_photo_uploads_due", "state", "id"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    farm_id: Mapped[UUID] = mapped_column(Uuid)
    owner_id: Mapped[UUID] = mapped_column(Uuid)
    section_id: Mapped[UUID] = mapped_column(Uuid)
    mutation_row_id: Mapped[UUID] = mapped_column(Uuid)
    media_id: Mapped[UUID] = mapped_column(Uuid, default=uuid4)
    local_media_id: Mapped[UUID] = mapped_column(Uuid)
    content_type: Mapped[str] = mapped_column(Text)
    byte_length: Mapped[int] = mapped_column(BigInteger)
    state: Mapped[str] = mapped_column(Text, default="awaiting_upload")
    sequence: Mapped[int] = mapped_column(BigInteger, default=1)
    error_code: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class PhotoAttempt(Base):
    """Retained attempt keys let cleanup avoid broad bucket scans."""

    __tablename__ = "photo_attempts"
    __table_args__ = (
        UniqueConstraint("upload_id", "sequence", name="uq_photo_attempts_sequence"),
        CheckConstraint(column("sequence") > 0, name="ck_photo_attempts_sequence"),
        CheckConstraint(
            column("attempt_count").between(0, MAX_CLAIMS), name="ck_photo_attempts_count"
        ),
        Index("ix_photo_attempts_cleanup", "cleaned_at", "terminal_at"),
    )
    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    upload_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("photo_uploads.id"))
    sequence: Mapped[int] = mapped_column(BigInteger)
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    form_expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    attempt_count: Mapped[int] = mapped_column(BigInteger, default=0)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    lease_token: Mapped[UUID | None] = mapped_column(Uuid)
    lease_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    source_generation: Mapped[str | None] = mapped_column(Text)
    clean_generation: Mapped[str | None] = mapped_column(Text)
    clean_sha256: Mapped[str | None] = mapped_column(Text)
    clean_size: Mapped[int | None] = mapped_column(BigInteger)
    width: Mapped[int | None] = mapped_column(BigInteger)
    height: Mapped[int | None] = mapped_column(BigInteger)
    terminal_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cleanup_token: Mapped[UUID | None] = mapped_column(Uuid)
    cleanup_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    cleaned_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class ForecastRun(Base):
    __tablename__ = "forecast_runs"
    __table_args__ = (
        CheckConstraint(
            column("status").in_(("staged", "active", "superseded")), name="ck_forecast_run_status"
        ),
        Index(
            "uq_forecast_one_active",
            "status",
            unique=True,
            postgresql_where=column("status") == "active",
            sqlite_where=column("status") == "active",
        ),
    )
    id: Mapped[str] = mapped_column(Text, primary_key=True)
    source_sha256: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text)
    payload: Mapped[dict[str, Any] | None] = mapped_column(JSON_DOCUMENT)
    failed_checks: Mapped[list[str]] = mapped_column(JSON_DOCUMENT)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


class ForecastState(Base):
    __tablename__ = "forecast_state"
    __table_args__ = (CheckConstraint(column("id") == 1, name="ck_forecast_state_singleton"),)
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True, autoincrement=False)
    active_run_id: Mapped[str | None] = mapped_column(Text, ForeignKey("forecast_runs.id"))


class WeatherJob(Base):
    """Transactional outbox and fenced lease, shared by rounded location only."""

    __tablename__ = "weather_jobs"
    __table_args__ = (
        CheckConstraint(column("latitude_tenths").between(-900, 900), name="ck_weather_lat"),
        CheckConstraint(column("longitude_tenths").between(-1800, 1799), name="ck_weather_lon"),
        CheckConstraint(column("last_year") - column("first_year") == 14, name="ck_weather_years"),
        CheckConstraint(
            column("status").in_(("pending", "processing", "ready")), name="ck_weather_status"
        ),
        Index("ix_weather_due", "policy_hash", "last_year", "status", "next_attempt_at"),
    )
    id: Mapped[str] = mapped_column(Text, primary_key=True)
    latitude_tenths: Mapped[int] = mapped_column(BigInteger)
    longitude_tenths: Mapped[int] = mapped_column(BigInteger)
    first_year: Mapped[int] = mapped_column(BigInteger)
    last_year: Mapped[int] = mapped_column(BigInteger)
    policy_hash: Mapped[str] = mapped_column(Text)
    status: Mapped[str] = mapped_column(Text, default="pending")
    attempt_count: Mapped[int] = mapped_column(BigInteger, default=0)
    next_attempt_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    lease_token: Mapped[UUID | None] = mapped_column(Uuid)
    lease_expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    completed_kind: Mapped[str | None] = mapped_column(Text)
    error_code: Mapped[str | None] = mapped_column(Text)


class WeatherRiskClimatology(Base):
    __tablename__ = "weather_risk_climatology"
    __table_args__ = (
        CheckConstraint(column("plant_month").between(1, 12), name="ck_weather_month"),
    )
    job_id: Mapped[str] = mapped_column(Text, ForeignKey("weather_jobs.id"), primary_key=True)
    crop: Mapped[str] = mapped_column(Text, primary_key=True)
    plant_month: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    payload: Mapped[dict[str, Any]] = mapped_column(JSON_DOCUMENT)
    computed_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class VoiceSessionRate(Base):
    __tablename__ = "voice_session_rates"
    owner_id: Mapped[UUID] = mapped_column(
        Uuid, ForeignKey("users.id", ondelete="CASCADE"), primary_key=True
    )
    hits: Mapped[list[float]] = mapped_column(JSON_DOCUMENT)


class PhotoRate(Base):
    __tablename__ = "photo_rates"
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id"), primary_key=True)
    hits: Mapped[list[float]] = mapped_column(JSON_DOCUMENT)


class RateLimitCounter(Base):
    """Durable sliding-window counter for auth/abuse limits (#9).

    Keyed by ``scope`` (e.g. ``signup_ip``, ``sms_phone``) plus a hashed
    subject so raw IPs/phones are never persisted. One row per scope+subject;
    a process restart cannot reset it because ``hits`` lives in the database.
    """

    __tablename__ = "rate_limit_counters"
    __table_args__ = (
        _nonblank("scope", "rate_limit_counters"),
        _max_length("scope", "rate_limit_counters", 40),
        _max_length("subject_hash", "rate_limit_counters", 64),
    )

    scope: Mapped[str] = mapped_column(Text, primary_key=True)
    subject_hash: Mapped[str] = mapped_column(Text, primary_key=True)
    hits: Mapped[list[float]] = mapped_column(JSON_DOCUMENT)
    in_flight: Mapped[int] = mapped_column(Integer, default=0, server_default="0")
    login_leases: Mapped[dict[str, float]] = mapped_column(
        JSON_DOCUMENT, default=dict, server_default="{}"
    )
    updated_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now(), onupdate=func.now()
    )


class ExportJob(Base):
    """A durable, owner-scoped account-data export job (#9).

    Job creation builds the artifact synchronously (the underlying query is
    cheap) but is modelled as a job — not a synchronous response — so the
    contract (status polling, an expiring signed download link, rate
    limiting, idempotent creation) matches the issue regardless of how long
    artifact assembly ever needs to take. ``download_token_hash`` is the only
    persisted trace of the download credential; the raw token is returned to
    the caller once, at creation, and never logged or stored.
    """

    __tablename__ = "export_jobs"
    __table_args__ = (
        _max_length("status", "export_jobs", 20),
        _max_length("format", "export_jobs", 4),
        _max_length("download_token_hash", "export_jobs", 64),
        CheckConstraint(
            column("status").in_(["pending", "ready", "failed", "expired"]),
            name="ck_export_jobs_status",
        ),
        CheckConstraint(column("format").in_(["json", "zip"]), name="ck_export_jobs_format"),
        Index("ix_export_jobs_owner_created", "owner_id", "created_at"),
    )

    id: Mapped[UUID] = mapped_column(Uuid, primary_key=True, default=uuid4)
    owner_id: Mapped[UUID] = mapped_column(Uuid, ForeignKey("users.id", ondelete="CASCADE"))
    status: Mapped[str] = mapped_column(Text, default="pending")
    format: Mapped[str] = mapped_column(Text)
    artifact: Mapped[bytes | None] = mapped_column(LargeBinary)
    download_token_hash: Mapped[str | None] = mapped_column(Text, unique=True)
    error_code: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    downloaded_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))


class IdempotencyRecord(Base):
    """Durable Idempotency-Key ledger (#9): one row per key+route.

    ``request_fingerprint`` lets a replay with a different payload be
    rejected instead of silently returning the first response. Responses are
    stored as their own JSON document so a replay never re-runs the mutation.
    """

    __tablename__ = "idempotency_records"
    __table_args__ = (
        _nonblank("route", "idempotency_records"),
        _max_length("scope", "idempotency_records", 128),
        _max_length("route", "idempotency_records", 60),
        _max_length("idempotency_key", "idempotency_records", 200),
        CheckConstraint(
            column("request_fingerprint").regexp_match("^[0-9a-f]{64}$"),
            name="ck_idempotency_records_request_fingerprint_hex",
        ),
    )

    route: Mapped[str] = mapped_column(Text, primary_key=True)
    scope: Mapped[str] = mapped_column(Text, primary_key=True, default="", server_default="")
    idempotency_key: Mapped[str] = mapped_column(Text, primary_key=True)
    request_fingerprint: Mapped[str] = mapped_column(Text)
    status_code: Mapped[int] = mapped_column(Integer)
    response_body: Mapped[dict[str, Any]] = mapped_column(JSON_DOCUMENT)
    created_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())


# Reusable ORM field annotations for future models (#8), not feature tables.
Point = Annotated[WKBElement, mapped_column(Geometry("POINT", srid=4326))]
Shape = Annotated[WKBElement, mapped_column(Geometry("MULTIPOLYGON", srid=4326))]
