"""ORM-only transactional scheduling, idempotent grid reuse and fenced publication."""

from datetime import timedelta
from uuid import uuid4

from sqlalchemy import or_, select
from sqlalchemy.exc import IntegrityError

from farmable_backend.models import Farm, Section, WeatherJob, WeatherRiskClimatology
from farmable_backend.record_access import db_now, utc
from farmable_backend.weather_policy import (
    GROWING_DAYS,
    POLICY_HASH,
    grid_cell,
    job_key,
    planting_years,
)


def enqueue_weather(session, boundary):
    cell = grid_cell(boundary)
    if cell is None:
        return None
    now = db_now(session)
    first, last = planting_years(now.date())
    key = job_key(cell, first, last)
    if session.get(WeatherJob, key) is None:
        try:
            # Concurrent sections/farms can share a cell. Losing the insert race
            # must not roll back the caller's section or sync-ledger transaction.
            with session.begin_nested():
                session.add(
                    WeatherJob(
                        id=key,
                        latitude_tenths=cell[0],
                        longitude_tenths=cell[1],
                        first_year=first,
                        last_year=last,
                        policy_hash=POLICY_HASH,
                        next_attempt_at=now,
                    )
                )
                session.flush()
        except IntegrityError:
            if session.get(WeatherJob, key) is None:
                raise
    return key


class WeatherJobs:
    def __init__(self, sessions, kind):
        if kind not in {"historical", "synthetic"}:
            raise ValueError("weather_kind")
        self.sessions, self.kind = sessions, kind

    def enqueue_existing(self, after=None):
        """Bounded startup/hourly catch-up for existing locations and annual rollover."""
        with self.sessions.begin() as session:
            query = (
                select(Section)
                .join(Farm, Section.farm_id == Farm.id)
                .where(
                    Section.deleted_at.is_(None),
                    Farm.deleted_at.is_(None),
                    Section.owner_id == Farm.owner_id,
                    Section.boundary.is_not(None),
                )
            )
            if after is not None:
                query = query.where(Section.id > after)
            sections = list(session.scalars(query.order_by(Section.id).limit(100)))
            for section in sections:
                enqueue_weather(session, section.boundary)
            return sections[-1].id if len(sections) == 100 else None

    def claim(self):
        with self.sessions.begin() as session:
            now = db_now(session)
            _, last = planting_years(now.date())
            job = session.scalar(
                select(WeatherJob)
                .where(
                    WeatherJob.policy_hash == POLICY_HASH,
                    WeatherJob.last_year == last,
                    or_(
                        (WeatherJob.status == "pending") & (WeatherJob.next_attempt_at <= now),
                        (WeatherJob.status == "processing") & (WeatherJob.lease_expires_at <= now),
                        (WeatherJob.status == "ready") & (WeatherJob.completed_kind != self.kind),
                    ),
                )
                .order_by(WeatherJob.next_attempt_at, WeatherJob.id)
                .with_for_update(skip_locked=True)
                .limit(1)
            )
            if job is None:
                return None
            job.status = "processing"
            job.attempt_count += 1
            job.lease_token = uuid4()
            job.lease_expires_at = now + timedelta(minutes=2)
            session.flush()
            session.expunge(job)
            return job

    def finish(self, claimed, rows, source_hash):
        if set(rows) != {(crop, month) for crop in GROWING_DAYS for month in range(1, 13)}:
            raise ValueError("weather_incomplete_grid")
        with self.sessions.begin() as session:
            job = session.get(WeatherJob, claimed.id, with_for_update=True)
            now = db_now(session)
            if not self.owns(job, claimed, now):
                return False
            for (crop, month), value in rows.items():
                row = session.get(WeatherRiskClimatology, (job.id, crop, month))
                if row is None:
                    row = WeatherRiskClimatology(job_id=job.id, crop=crop, plant_month=month)
                    session.add(row)
                row.payload = {**value, "data_kind": self.kind, "source_sha256": source_hash}
                row.computed_at = now
            job.status, job.completed_kind, job.error_code = "ready", self.kind, None
            job.lease_token = job.lease_expires_at = None
            return True

    @staticmethod
    def owns(job, claimed, now):
        return (
            job is not None
            and job.status == "processing"
            and job.lease_token == claimed.lease_token
            and job.lease_expires_at is not None
            and utc(job.lease_expires_at) > now
        )

    def fail(self, claimed):
        with self.sessions.begin() as session:
            job = session.get(WeatherJob, claimed.id, with_for_update=True)
            now = db_now(session)
            if not self.owns(job, claimed, now):
                return False
            job.status, job.error_code = "pending", "weather_unavailable"
            # Retry indefinitely at a bounded rate, without holding DB/network leases.
            job.next_attempt_at = now + timedelta(
                seconds=min(3600, 60 * 2 ** min(job.attempt_count - 1, 6))
            )
            job.lease_token = job.lease_expires_at = None
            return True
