"""Deterministic records used by the explicit Farmable demo seed command."""

from datetime import date
from decimal import Decimal
from uuid import UUID

from sqlalchemy.orm import Session

from farmable_backend.models import Farm, FarmTask, Observation, Planting, Section, User

DEMO_OWNER_ID = UUID("10000000-0000-4000-8000-000000000001")
DEMO_FARM_ID = UUID("10000000-0000-4000-8000-000000000002")
DEMO_CABBAGE_SECTION_ID = UUID("10000000-0000-4000-8000-000000000003")
DEMO_NORTH_SECTION_ID = UUID("10000000-0000-4000-8000-000000000004")
DEMO_OBSERVATION_ID = UUID("10000000-0000-4000-8000-000000000005")
DEMO_TASK_ID = UUID("10000000-0000-4000-8000-000000000006")
DEMO_PLANTING_ID = UUID("10000000-0000-4000-8000-000000000007")


class DemoSeedConflictError(RuntimeError):
    """The stable demo ID already belongs to unexpected data."""


def seed_demo_farm(session: Session) -> Farm:
    """Create the stable minimum demo state; repeated calls are harmless."""
    existing = session.get(Farm, DEMO_FARM_ID)
    if existing is not None:
        if existing.owner_id != DEMO_OWNER_ID or existing.name != "Mahlangu Demo Farm":
            raise DemoSeedConflictError("the demo farm id is already in use")
        return existing

    owner = session.get(User, DEMO_OWNER_ID)
    if owner is None:
        owner = User(id=DEMO_OWNER_ID)
        session.add(owner)
        session.flush()
    farm = Farm(
        id=DEMO_FARM_ID,
        owner_id=DEMO_OWNER_ID,
        name="Mahlangu Demo Farm",
        sync_state="synced",
    )
    cabbage = Section(
        id=DEMO_CABBAGE_SECTION_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        name="Cabbage Field",
        area_m2=Decimal("400.00"),
        sync_state="synced",
    )
    north = Section(
        id=DEMO_NORTH_SECTION_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        name="North Plot",
        area_m2=Decimal("300.00"),
        sync_state="synced",
    )
    planting = Planting(
        id=DEMO_PLANTING_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        section_id=cabbage.id,
        crop="cabbage",
        planted_on=date(2026, 8, 10),
        sync_state="synced",
    )
    observation = Observation(
        id=DEMO_OBSERVATION_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        section_id=cabbage.id,
        type="health",
        note="Lower leaves checked; crop remains suitable for the demo.",
        health_status="normal",
        created_by_voice=False,
        sync_state="synced",
    )
    task = FarmTask(
        id=DEMO_TASK_ID,
        farm_id=farm.id,
        owner_id=DEMO_OWNER_ID,
        section_id=cabbage.id,
        title="Water Cabbage Field",
        description="Upcoming watering task for the voice-edit demonstration.",
        due_date=date(2026, 9, 25),
        status="pending",
        expected_cost_cents=0,
        sync_state="synced",
    )
    session.add(farm)
    session.flush()
    session.add_all((cabbage, north))
    session.flush()
    session.add_all((planting, observation, task))
    session.flush()
    return farm
