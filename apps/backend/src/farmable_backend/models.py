from datetime import datetime
from typing import Annotated, Any

from geoalchemy2 import Geometry
from geoalchemy2.elements import WKBElement
from sqlalchemy import (
    JSON,
    BigInteger,
    CheckConstraint,
    DateTime,
    Identity,
    Text,
    UniqueConstraint,
    column,
    func,
)
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

# Spinach is sold by bunch or kilogram, so only these crops get a per-plant formula (#16).
WEIGHED_CROPS = ("cabbage", "tomato")


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
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


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
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True), server_default=func.now()
    )


# Reusable ORM field annotations for future models (#8), not feature tables.
Point = Annotated[WKBElement, mapped_column(Geometry("POINT", srid=4326))]
Shape = Annotated[WKBElement, mapped_column(Geometry("MULTIPOLYGON", srid=4326))]
