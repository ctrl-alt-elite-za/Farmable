"""Validate immutable snapshots and atomically publish/roll back through the ORM."""

import hashlib
import re
from dataclasses import dataclass
from decimal import ROUND_HALF_UP, Decimal
from uuid import UUID

from pydantic import ValidationError
from sqlalchemy import select
from sqlalchemy.orm import Session

from farmable_backend.forecast_contract import (
    CROPS,
    SAMPLE_WARNING,
    Crop,
    ForecastBundle,
    Mode,
    Outlook,
    PriceRange,
)
from farmable_backend.models import Farm, ForecastRun, ForecastState, Section
from farmable_backend.record_access import ApiError, authenticate, db_now
from farmable_backend.weather_outlook import cached_weather

MAX_BUNDLE_BYTES = 1_048_576


@dataclass(frozen=True)
class ImportResult:
    run_id: str
    status: str
    failed_checks: tuple[str, ...] = ()


def expected_kind(mode: Mode) -> str | None:
    return {"sample": "synthetic", "historical": "historical"}.get(mode)


def quality_checks(
    bundle: ForecastBundle, previous: ForecastBundle | None, mode: Mode
) -> list[str]:
    failures = []
    keys = [(row.crop, row.plant_month) for row in bundle.rows]
    if len(keys) != 96 or set(keys) != {(crop, month) for crop in CROPS for month in range(1, 13)}:
        failures.append("crop_month_coverage")
    if any(min(row.p10, row.p50, row.p90) <= 0 for row in bundle.rows):
        failures.append("prices_positive")
    if any(not row.p10 <= row.p50 <= row.p90 for row in bundle.rows):
        failures.append("quantiles_ordered")
    if bundle.data_kind != expected_kind(mode):
        failures.append("data_mode_mismatch")
    if any((row.method == "fixture") != (bundle.data_kind == "synthetic") for row in bundle.rows):
        failures.append("method_kind_mismatch")
    if len({source.name for source in bundle.sources}) != len(bundle.sources):
        failures.append("duplicate_sources")
    # Synthetic values are never a quality baseline for historical results.
    if previous is not None and previous.data_kind == bundle.data_kind:
        if bundle.as_of < previous.as_of:
            failures.append("as_of_regression")
        baseline = {(row.crop, row.plant_month): row.p50 for row in previous.rows}
        if any(
            (old := baseline.get((row.crop, row.plant_month))) is not None
            and abs(row.p50 - old) > old * Decimal("0.5")
            for row in bundle.rows
        ):
            failures.append("p50_jump")
    return sorted(failures)


def locked_state(session: Session) -> ForecastState:
    state = session.scalar(select(ForecastState).where(ForecastState.id == 1).with_for_update())
    if state is None:
        raise ApiError(503, "forecast_migration_required")
    return state


def publish(session: Session, state: ForecastState, run: ForecastRun) -> None:
    if state.active_run_id == run.id:
        return
    if state.active_run_id is not None:
        previous = session.get(ForecastRun, state.active_run_id)
        if previous is None:
            raise ApiError(503, "forecast_state_invalid")
        previous.status = "superseded"
        session.flush()  # Release the partial unique index before activating the next run.
    run.status = "active"
    state.active_run_id = run.id


def import_bundle(sessions, run_id: str, raw: bytes, mode: Mode) -> ImportResult:
    if re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", run_id) is None:
        raise ValueError("invalid_run_id")
    if len(raw) > MAX_BUNDLE_BYTES:
        raise ValueError("bundle_too_large")
    digest = hashlib.sha256(raw).hexdigest()
    bundle = None
    failures = []
    try:
        bundle = ForecastBundle.model_validate_json(raw)
    except ValidationError:
        failures.append("schema")
    if bundle is not None and bundle.run_id != run_id:
        failures.append("run_id_mismatch")
    with sessions.begin() as session:
        state = locked_state(session)
        existing = session.get(ForecastRun, run_id)
        if existing is not None:
            if existing.source_sha256 != digest:
                return ImportResult(run_id, "rejected", ("run_id_conflict",))
            return ImportResult(run_id, existing.status, tuple(existing.failed_checks))
        previous = session.get(ForecastRun, state.active_run_id) if state.active_run_id else None
        if bundle is not None:
            prior = ForecastBundle.model_validate(previous.payload) if previous else None
            failures.extend(quality_checks(bundle, prior, mode))
            if bundle.as_of > db_now(session):
                failures.append("as_of_future")
        run = ForecastRun(
            id=run_id,
            source_sha256=digest,
            status="staged",
            payload=bundle.model_dump(mode="json") if bundle is not None else None,
            failed_checks=sorted(set(failures)),
        )
        session.add(run)
        session.flush()
        if not run.failed_checks:
            publish(session, state, run)
        return ImportResult(run_id, run.status, tuple(run.failed_checks))


def activate(sessions, run_id: str, mode: Mode) -> None:
    with sessions.begin() as session:
        state = locked_state(session)
        run = session.get(ForecastRun, run_id)
        # Rollback is only to a previously accepted run, never a quality bypass.
        if run is None or run.status not in {"active", "superseded"} or run.failed_checks:
            raise ApiError(409, "forecast_not_previously_active")
        bundle = ForecastBundle.model_validate(run.payload)
        if bundle.data_kind != expected_kind(mode):
            raise ApiError(409, "forecast_mode_mismatch")
        publish(session, state, run)


def outlook(
    sessions,
    authorization: str | None,
    section_id: UUID,
    crop: Crop,
    plant_month: int,
    mode: Mode,
    integrations_mode: str = "disabled",
) -> Outlook:
    with sessions() as session:
        owner = authenticate(session, authorization)
        section = session.scalar(
            select(Section)
            .join(Farm, Section.farm_id == Farm.id)
            .where(
                Section.id == section_id,
                Section.owner_id == owner,
                Section.deleted_at.is_(None),
                Farm.owner_id == owner,
                Farm.deleted_at.is_(None),
            )
        )
        if section is None:
            raise ApiError(404, "not_found")
        if mode == "disabled":
            raise ApiError(503, "forecast_disabled")
        # One statement obtains an internally consistent snapshot while importers
        # change the pointer/status in another transaction; no weather/network I/O.
        run = session.scalar(
            select(ForecastRun)
            .join(ForecastState, ForecastState.active_run_id == ForecastRun.id)
            .where(ForecastState.id == 1, ForecastRun.status == "active")
        )
        if run is None:
            raise ApiError(503, "forecast_unavailable")
        bundle = ForecastBundle.model_validate(run.payload)
        if bundle.data_kind != expected_kind(mode):
            raise ApiError(503, "forecast_mode_mismatch")
        row = next(
            (row for row in bundle.rows if row.crop == crop and row.plant_month == plant_month),
            None,
        )
        if row is None:
            raise ApiError(503, "forecast_incomplete")
        return Outlook(
            run_id=run.id,
            data_kind=bundle.data_kind,
            warning=SAMPLE_WARNING if bundle.data_kind == "synthetic" else None,
            forecast_as_of=bundle.as_of,
            crop=crop,
            plant_month=plant_month,
            harvest_month=(plant_month - 1 + row.growing_months) % 12 + 1,
            price_range=PriceRange(p10=row.p10, p50=row.p50, p90=row.p90),
            method=row.method,
            cost_per_ha=row.cost_per_ha,
            yield_kg_per_ha=row.yield_kg_per_ha,
            break_even_price_per_kg=(row.cost_per_ha / row.yield_kg_per_ha).quantize(
                Decimal("0.0001"), rounding=ROUND_HALF_UP
            ),
            weather_risk=cached_weather(
                session, section.boundary, crop, plant_month, integrations_mode
            ),
            assumptions=bundle.assumptions,
        )
