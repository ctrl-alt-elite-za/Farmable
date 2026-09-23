"""Read-only previews and atomic, explicit confirmations through the existing sync ledger."""

from datetime import timedelta
from decimal import Decimal
from uuid import uuid4
from zoneinfo import ZoneInfo

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError

from farmable_backend.farm_records import _fingerprint
from farmable_backend.forecast_contract import SAMPLE_WARNING, ForecastBundle
from farmable_backend.forecasts import expected_kind, quality_checks
from farmable_backend.models import (
    ForecastRun,
    ForecastState,
    PlanRevision,
    SavedPlan,
    SyncChange,
    SyncMutation,
    WeatherJob,
)
from farmable_backend.planning.contracts import ConfirmedPlan, PlanHistory, PlanHistoryEntry
from farmable_backend.planning.history import preserve
from farmable_backend.planning.production import calculate
from farmable_backend.record_access import (
    ApiError,
    authenticate,
    db_now,
    farm_scope,
    section_scope,
    utc,
)
from farmable_backend.weather_outlook import cached_weather
from farmable_backend.weather_policy import grid_cell, job_key, planting_years


class Planner:
    def __init__(self, sessions, mode, integrations_mode):
        self.sessions, self.mode, self.integrations_mode = sessions, mode, integrations_mode

    def history(self, auth, farm_id, plan_id, before_version, limit):
        with self.sessions.begin() as session:
            owner = authenticate(session, auth)
            farm_scope(session, owner, farm_id)
            record = session.get(SavedPlan, plan_id)
            if record is None or (record.owner_id, record.farm_id) != (owner, farm_id):
                raise ApiError(404, "not_found")
            query = select(PlanRevision).where(
                PlanRevision.owner_id == owner,
                PlanRevision.farm_id == farm_id,
                PlanRevision.plan_id == plan_id,
            )
            if before_version is not None:
                query = query.where(PlanRevision.version < before_version)
            rows = session.scalars(
                query.order_by(PlanRevision.version.desc()).limit(limit + 1)
            ).all()
            return PlanHistory(
                revisions=[
                    PlanHistoryEntry(
                        version=row.version,
                        section_id=row.section_id,
                        origin=row.origin,
                        recorded_at=utc(row.recorded_at),
                        snapshot=row.snapshot,
                    )
                    for row in rows[:limit]
                ],
                next_before_version=rows[limit - 1].version if len(rows) > limit else None,
            )

    def preview(self, auth, farm_id, request):
        with self.sessions.begin() as session:
            owner = authenticate(session, auth)
            farm_scope(session, owner, farm_id, lock=True)
            section = section_scope(session, owner, farm_id, request.section_id, lock=True)
            return self.snapshot(session, section, request)

    def snapshot(self, session, section, request):
        today = db_now(session).astimezone(ZoneInfo("Africa/Johannesburg")).date()
        if not today <= request.planting_date <= today + timedelta(days=365):
            raise ApiError(422, "planting_date_out_of_range")
        if section.area_m2 is None or not Decimal(1) <= section.area_m2 <= Decimal(1_000_000):
            raise ApiError(422, "section_area_required")
        # Same lock as activation/rollback: all crops and confirmation use one active run.
        state = session.get(ForecastState, 1, with_for_update=True)
        run = (
            session.get(ForecastRun, state.active_run_id) if state and state.active_run_id else None
        )
        if self.mode == "disabled" or run is None or run.status != "active" or run.failed_checks:
            raise ApiError(503, "outlook_unavailable")
        try:
            bundle = ForecastBundle.model_validate(run.payload)
        except ValidationError:
            raise ApiError(503, "outlook_unavailable") from None
        if (
            bundle.data_kind != expected_kind(self.mode)
            or bundle.run_id != run.id
            or quality_checks(bundle, None, self.mode)
        ):
            raise ApiError(503, "outlook_unavailable")
        cell = grid_cell(section.boundary)
        if cell is not None:
            first, last = planting_years(today)
            session.get(WeatherJob, job_key(cell, first, last), with_for_update=True)
        rows = {
            row.crop: row for row in bundle.rows if row.plant_month == request.planting_date.month
        }
        weather = {
            item.crop: cached_weather(
                session,
                section.boundary,
                item.crop,
                request.planting_date.month,
                self.integrations_mode,
            ).model_dump(mode="json")
            for item in request.crops
        }
        source = {
            "run_id": run.id,
            "source_sha256": run.source_sha256,
            "forecast_as_of": bundle.as_of.isoformat(),
            "data_kind": bundle.data_kind,
            "warning": SAMPLE_WARNING if bundle.data_kind == "synthetic" else None,
            "price_basis_year": bundle.price_basis_year,
            "assumptions": bundle.assumptions,
            "rows": [
                rows[item.crop].model_dump(mode="json")
                for item in sorted(request.crops, key=lambda c: c.crop)
            ],
            "weather": weather,
            "boundary_hash": _fingerprint({"boundary": section.boundary}),
        }
        return calculate(request, section, rows, source)

    def confirm(self, auth, farm_id, payload):
        if not payload.confirmed:
            raise ApiError(422, "explicit_confirmation_required")
        fingerprint = _fingerprint(payload.model_dump(mode="json"))
        try:
            with self.sessions.begin() as session:
                owner = authenticate(session, auth)
                farm_scope(session, owner, farm_id, lock=True)
                section = section_scope(
                    session, owner, farm_id, payload.request.section_id, lock=True
                )
                mutation = session.scalar(
                    select(SyncMutation).where(SyncMutation.mutation_id == payload.mutation_id)
                )
                record = session.get(SavedPlan, payload.plan_id, with_for_update=True)
                if mutation is not None:
                    if (
                        mutation.owner_id,
                        mutation.farm_id,
                        mutation.record_type,
                        mutation.operation,
                        mutation.record_id,
                        mutation.request_fingerprint,
                    ) != (owner, farm_id, "plan", "confirm_plan", payload.plan_id, fingerprint):
                        raise ApiError(409, "mutation_conflict")
                    self.check_record(record, owner, farm_id, section.id)
                    change = session.scalar(
                        select(SyncChange).where(SyncChange.mutation_id == mutation.id)
                    )
                    if (
                        change is None
                        or change.version != record.version
                        or record.status != "approved"
                    ):
                        raise ApiError(409, "plan_state_changed")
                    # An accepted retry never recalculates, writes or revives a deleted plan.
                    return self.receipt(record, True)
                if record is not None:
                    self.check_record(record, owner, farm_id, section.id)
                    if record.version != payload.expected_version:
                        raise ApiError(409, "revision_conflict")
                elif payload.expected_version != 0:
                    raise ApiError(409, "revision_conflict")
                preview = self.snapshot(session, section, payload.request)
                if preview.snapshot_hash != payload.snapshot_hash:
                    raise ApiError(409, "plan_stale")
                chosen = next((p for p in preview.candidates if p.id == payload.candidate_id), None)
                if chosen is None:
                    raise ApiError(409, "plan_candidate_unavailable")
                saved = {
                    "schema_version": 1,
                    "engine_version": preview.engine_version,
                    "request": preview.request.model_dump(mode="json"),
                    "snapshot_hash": preview.snapshot_hash,
                    "section_version": section.version,
                    "source": preview.source,
                    "assumptions": preview.assumptions,
                    "candidate": chosen.model_dump(mode="json"),
                }
                operation = "create" if record is None else "update"
                if record is None:
                    record = SavedPlan(
                        id=payload.plan_id,
                        farm_id=farm_id,
                        owner_id=owner,
                        section_id=section.id,
                        version=1,
                    )
                    session.add(record)
                else:
                    preserve(session, record)
                    record.version += 1
                record.status, record.plan = "approved", saved
                record.approved_at, record.sync_state = db_now(session), "synced"
                mutation = SyncMutation(
                    id=uuid4(),
                    mutation_id=payload.mutation_id,
                    owner_id=owner,
                    farm_id=farm_id,
                    record_type="plan",
                    record_id=record.id,
                    operation="confirm_plan",
                    request_fingerprint=fingerprint,
                )
                session.add(mutation)
                session.flush()
                preserve(session, record, "planner_confirmation")
                session.add(
                    SyncChange(
                        owner_id=owner,
                        farm_id=farm_id,
                        mutation_id=mutation.id,
                        record_type="plan",
                        record_id=record.id,
                        operation=operation,
                        version=record.version,
                    )
                )
                session.flush()
                return self.receipt(record, False)
        except IntegrityError:
            raise ApiError(409, "mutation_conflict") from None

    @staticmethod
    def check_record(record, owner, farm_id, section_id):
        if record is None or (record.owner_id, record.farm_id, record.section_id) != (
            owner,
            farm_id,
            section_id,
        ):
            raise ApiError(404, "not_found")
        if record.deleted_at is not None:
            raise ApiError(409, "record_deleted")

    @staticmethod
    def receipt(record, replayed):
        if record.approved_at is None:
            raise ApiError(409, "plan_state_changed")
        return ConfirmedPlan(
            id=record.id,
            version=record.version,
            approved_at=utc(record.approved_at),
            replayed=replayed,
        )
