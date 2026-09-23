from alembic import context
from farmable_backend.config import Settings
from farmable_backend.database import make_engine
from farmable_backend.models import Base

_SPATIAL_TABLES = {
    "spatial_ref_sys",
    "geometry_columns",
    "geography_columns",
    "raster_columns",
    "raster_overviews",
}
_MIGRATION_OWNED_INDEXES = {
    "ix_auth_sessions_retention",
    "ix_verification_challenges_retention",
    "ix_idempotency_records_retention",
    "ix_rate_limit_counters_retention",
    "ix_export_jobs_retention",
}


def include_name(name, type_, parent_names):
    if type_ == "table":
        return name not in _SPATIAL_TABLES and not name.startswith("procrastinate_")
    return True


def include_object(object_, name, type_, reflected, compare_to):
    if type_ == "index" and name in _MIGRATION_OWNED_INDEXES:
        return False
    return True


def run_migrations() -> None:
    if context.is_offline_mode():
        # Read-only generated SQL for CI linting, never executed by application code.
        context.configure(
            dialect_name="postgresql",
            target_metadata=Base.metadata,
            literal_binds=True,
            dialect_opts={"paramstyle": "named"},
            include_object=include_object,
        )
        with context.begin_transaction():
            context.run_migrations()
        return
    engine = make_engine(Settings(), migration=True)
    try:
        with engine.connect() as connection:
            context.configure(
                connection=connection,
                target_metadata=Base.metadata,
                include_name=include_name,
                include_object=include_object,
                compare_type=True,
                version_table_schema=context.config.attributes.get("version_table_schema"),
            )
            with context.begin_transaction():
                context.run_migrations()
    finally:
        engine.dispose()


run_migrations()
