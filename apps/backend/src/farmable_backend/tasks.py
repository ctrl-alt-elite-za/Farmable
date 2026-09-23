import logging

import procrastinate
from sqlalchemy.engine import make_url

from farmable_backend.config import Settings
from farmable_backend.database import CONNECTION_OPTIONS, Database
from farmable_backend.logging import correlation_id, request_id
from farmable_backend.retention import cleanup


def create_task_app(settings: Settings) -> procrastinate.App:
    url = make_url(settings.database_url.get_secret_value())
    connector = procrastinate.PsycopgConnector(
        conninfo=url.set(drivername="postgresql").render_as_string(hide_password=False),
        kwargs={"connect_timeout": 5, "options": CONNECTION_OPTIONS},
        min_size=1,
        max_size=4,
        timeout=5,
    )
    app = procrastinate.App(connector=connector)

    @app.task(name="example_job", queue="default")
    async def example_job(request_id_value: str | None = None) -> None:
        context = request_id.set(correlation_id(request_id_value))
        try:
            logging.getLogger(__name__).info("Example job completed")
        finally:
            request_id.reset(context)

    @app.task(name="retention_cleanup", queue="default")
    async def retention_cleanup(request_id_value: str | None = None) -> None:
        context = request_id.set(correlation_id(request_id_value))
        database = Database(settings)
        try:
            cleanup(database.sessions)
        finally:
            database.close()
            request_id.reset(context)

    return app
