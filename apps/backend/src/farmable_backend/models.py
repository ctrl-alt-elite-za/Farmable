from typing import Annotated

from geoalchemy2 import Geometry
from geoalchemy2.elements import WKBElement
from sqlalchemy import JSON, DateTime, Integer, String, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    """Declarative base for Farmable's ORM models."""


class DetectorModel(Base):
    __tablename__ = "detector_models"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    version: Mapped[str] = mapped_column(String(128), unique=True, index=True)
    artifact_uri: Mapped[str] = mapped_column(String(1024))
    artifact_sha256: Mapped[str] = mapped_column(String(64))
    metrics: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[object] = mapped_column(DateTime(timezone=True), server_default=func.now())


class WeightFormula(Base):
    __tablename__ = "weight_formulas"

    id: Mapped[int] = mapped_column(Integer, primary_key=True)
    crop: Mapped[str] = mapped_column(String(32))
    version: Mapped[str] = mapped_column(String(128))
    formula: Mapped[dict] = mapped_column(JSON)
    created_at: Mapped[object] = mapped_column(DateTime(timezone=True), server_default=func.now())


# Reusable ORM field annotations for future models (#8), not feature tables.
Point = Annotated[WKBElement, mapped_column(Geometry("POINT", srid=4326))]
Shape = Annotated[WKBElement, mapped_column(Geometry("MULTIPOLYGON", srid=4326))]
