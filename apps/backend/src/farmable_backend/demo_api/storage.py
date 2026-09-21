import hashlib
import secrets
import threading
from collections.abc import Callable
from decimal import Decimal
from pathlib import Path
from typing import Any
from uuid import UUID, uuid4

from sqlalchemy import JSON, String, create_engine, func, select
from sqlalchemy.engine import URL
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column

from .geometry import boundary_area, example_rectangle
from .schemas import Boundary, Dashboard, DemoFarm, DemoSection


class DemoError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


class DemoBase(DeclarativeBase):
    """Isolated local store, NEVER included in production Base/Alembic metadata."""


class DemoState(DemoBase):
    __tablename__ = "farmable_demo_states"
    id: Mapped[str] = mapped_column(String(36), primary_key=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True, index=True)
    payload: Mapped[dict[str, Any]] = mapped_column(JSON)


def seed_farm(farm_id: UUID | None = None) -> DemoFarm:
    sections = []
    for name, crop, width, height, offset in (
        ("Existing cabbage", "cabbage", 5, 8, 0),
        ("Existing spinach", "spinach", 5, 8, 8),
        ("Available section", None, 20, 20, 16),
    ):
        boundary = Boundary(coordinates=(example_rectangle(width, height, offset),))
        sections.append(
            DemoSection.model_validate(
                {
                    "id": uuid4(),
                    "name": name,
                    "current_crop": crop,
                    "area_m2": boundary_area(boundary.coordinates[0]),
                    "boundary": boundary,
                    "area_source": "example_boundary",
                }
            )
        )
    return DemoFarm(id=farm_id or uuid4(), sections=tuple(sections))


def dashboard(farm: DemoFarm) -> Dashboard:
    active = {section.planned_plan_id for section in farm.sections}
    return Dashboard(
        farm_id=farm.id,
        name=farm.name,
        sections=farm.sections,
        total_section_area_m2=sum(
            (section.area_m2 for section in farm.sections), start=Decimal("0")
        ),
        approved_plans=tuple(plan for plan in farm.plans if plan.id in active),
    )


class DemoStore:
    """One local API worker. Lock read/modify/write transactions to avoid lost updates."""

    def __init__(self, path: Path):
        self.engine = create_engine(
            URL.create("sqlite+pysqlite", database=str(path)),
            connect_args={"check_same_thread": False, "timeout": 5},
            hide_parameters=True,
        )
        self.lock = threading.RLock()

    def close(self) -> None:
        self.engine.dispose()

    @staticmethod
    def token_hash(token: str) -> str:
        if len(token) != 43 or not all(c.isascii() and (c.isalnum() or c in "-_") for c in token):
            raise DemoError(401, "invalid_demo_session", "Create or restore a demo session")
        return hashlib.sha256(token.encode()).hexdigest()

    def create(self) -> tuple[str, DemoFarm]:
        with self.lock, Session(self.engine) as session, session.begin():
            if (session.scalar(select(func.count()).select_from(DemoState)) or 0) >= 32:
                raise DemoError(429, "demo_session_limit", "Local demo session limit reached")
            token = secrets.token_urlsafe(32)
            farm = seed_farm()
            session.add(
                DemoState(
                    id=str(farm.id),
                    token_hash=self.token_hash(token),
                    payload=farm.model_dump(mode="json"),
                )
            )
        return token, farm

    def update(self, token: str, change: Callable[[DemoFarm], DemoFarm]) -> DemoFarm:
        digest = self.token_hash(token)
        with self.lock, Session(self.engine) as session, session.begin():
            row = session.scalar(select(DemoState).where(DemoState.token_hash == digest))
            if row is None:
                raise DemoError(401, "invalid_demo_session", "Create or restore a demo session")
            farm = change(DemoFarm.model_validate(row.payload))
            farm = DemoFarm.model_validate(farm.model_dump())
            row.payload = farm.model_dump(mode="json")
        return farm

    def read(self, token: str) -> DemoFarm:
        digest = self.token_hash(token)
        with self.lock, Session(self.engine) as session:
            row = session.scalar(select(DemoState).where(DemoState.token_hash == digest))
            if row is None:
                raise DemoError(401, "invalid_demo_session", "Create or restore a demo session")
            return DemoFarm.model_validate(row.payload)


def initialize_storage(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    store = DemoStore(path)
    try:
        DemoBase.metadata.create_all(store.engine)
    finally:
        store.close()
