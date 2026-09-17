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


def include_name(name, type_, parent_names):
    if type_ == "table":
        return name not in _SPATIAL_TABLES and not name.startswith("procrastinate_")
    return True


def run_migrations() -> None:
    if context.is_offline_mode():
        raise RuntimeError("Use online migrations; offline SQL scripts are not supported")
    engine = make_engine(Settings())
    try:
        with engine.connect() as connection:
            context.configure(
                connection=connection,
                target_metadata=Base.metadata,
                include_name=include_name,
                compare_type=True,
            )
            with context.begin_transaction():
                context.run_migrations()
    finally:
        engine.dispose()


run_migrations()
