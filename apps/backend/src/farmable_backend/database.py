from datetime import datetime, timedelta

from sqlalchemy import BigInteger, DateTime, String, create_engine, func, select
from sqlalchemy.orm import DeclarativeBase, Mapped, Session, mapped_column, sessionmaker

from farmable_backend.config import Settings

# The image's Tiger geocoder adds vendor schemas to the database search path.
# Keep ORM resolution/reflection in public without executing a SQL SET statement.
CONNECTION_OPTIONS = "-c statement_timeout=5000 -c search_path=public"


class ExternalBase(DeclarativeBase):
    """Read-only mappings, never included in our Alembic metadata."""


class PostgresDatabase(ExternalBase):
    __tablename__ = "pg_database"
    __table_args__ = {"schema": "pg_catalog"}
    datname: Mapped[str] = mapped_column(String, primary_key=True)


class WorkerHeartbeat(ExternalBase):
    # Owned and migrated by Procrastinate, not by the application's ORM metadata.
    __tablename__ = "procrastinate_workers"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    last_heartbeat: Mapped[datetime] = mapped_column(DateTime(timezone=True))


class QueueJob(ExternalBase):
    """Read-only job status for integration verification."""

    __tablename__ = "procrastinate_jobs"
    id: Mapped[int] = mapped_column(BigInteger, primary_key=True)
    status: Mapped[str] = mapped_column(String)


def make_engine(settings: Settings, *, migration: bool = False):
    options = CONNECTION_OPTIONS
    if migration:
        options += " -c lock_timeout=1000"
    return create_engine(
        settings.database_url.get_secret_value(),
        connect_args={"connect_timeout": 5, "options": options},
        pool_timeout=5,
        pool_pre_ping=True,
        hide_parameters=True,
    )


class Database:
    def __init__(self, settings: Settings):
        self.engine = make_engine(settings)
        self.sessions = sessionmaker(self.engine, expire_on_commit=False)

    def readiness(self) -> dict[str, str]:
        result = {"database": "down", "worker": "down"}
        try:
            with self.sessions() as session:
                if (
                    session.scalar(
                        select(PostgresDatabase).where(
                            PostgresDatabase.datname == func.current_database()
                        )
                    )
                    is None
                ):
                    return result
            result["database"] = "ok"
        except Exception:
            return result
        try:
            with self.sessions() as session:
                if live_worker(session):
                    result["worker"] = "ok"
        except Exception:
            return result  # Health responses deliberately omit dependency exception details.
        return result

    def close(self) -> None:
        self.engine.dispose()


def live_worker(session: Session) -> bool:
    # Use the database clock, not the API host clock. Default heartbeat interval is 10s.
    return (
        session.scalar(
            select(WorkerHeartbeat.id)
            .where(WorkerHeartbeat.last_heartbeat > func.now() - timedelta(seconds=30))
            .limit(1)
        )
        is not None
    )
