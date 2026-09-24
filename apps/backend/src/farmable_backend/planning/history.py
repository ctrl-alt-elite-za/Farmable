"""Snapshot accepted plan versions within the caller's existing farm-locked transaction."""

from copy import deepcopy

from sqlalchemy import select

from farmable_backend.models import PlanRevision
from farmable_backend.record_access import utc


def preserve(session, record, origin="baseline"):
    # The farm/plan lock serializes both sync and planner writes. The unique
    # constraint is a second guard, not an upsert: never replace an old snapshot.
    existing = session.scalar(
        select(PlanRevision.id).where(
            PlanRevision.plan_id == record.id, PlanRevision.version == record.version
        )
    )
    if existing is not None:
        return
    session.add(
        PlanRevision(
            plan_id=record.id,
            owner_id=record.owner_id,
            farm_id=record.farm_id,
            section_id=record.section_id,
            version=record.version,
            origin=origin,
            snapshot={
                "status": record.status,
                "plan": deepcopy(record.plan),
                "approved_at": utc(record.approved_at).isoformat() if record.approved_at else None,
                "deleted_at": utc(record.deleted_at).isoformat() if record.deleted_at else None,
                "created_at": utc(record.created_at).isoformat(),
                "updated_at": utc(record.updated_at).isoformat(),
            },
        )
    )
