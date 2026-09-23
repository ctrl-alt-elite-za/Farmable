import asyncio
import logging
import sys

from procrastinate.exceptions import AlreadyEnqueued

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.gcs_photos import create_gcs_photos
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.logging import configure_logging
from farmable_backend.photo_worker import PhotoWorker
from farmable_backend.tasks import create_task_app
from farmable_backend.weather_worker import WeatherWorker


async def run() -> None:
    services_settings = ServiceSettings()  # Refuse unsafe fault/fake flags before connecting.
    settings = Settings()
    configure_logging(settings.log_level)
    app = create_task_app(settings)
    database = None
    photos = None
    photo_task = None
    services = None
    weather = None
    weather_task = None
    try:
        async with app.open_async():
            tasks = getattr(app, "tasks", {})
            if isinstance(tasks, dict) and "retention_cleanup" in tasks:
                try:
                    await (
                        tasks["retention_cleanup"]
                        .configure(queueing_lock="retention-cleanup", schedule_in={"hours": 1})
                        .defer_async()
                    )
                except AlreadyEnqueued:
                    pass
                except Exception:
                    # A worker restart must not prevent the main queue from
                    # starting if a duplicate scheduled cleanup is present.
                    logging.getLogger(__name__).exception("Could not schedule retention cleanup")
            if settings.photo_bucket or services_settings.integrations_mode != "disabled":
                database = Database(settings)
            if database is not None and services_settings.integrations_mode != "disabled":
                services = ServiceRegistry(services_settings)
                weather = WeatherWorker(database.sessions, services.open_meteo)
                weather_task = asyncio.create_task(weather.run())
            if database is not None and settings.photo_bucket:
                photos = PhotoWorker(database.sessions, lambda: create_gcs_photos(settings))
                photo_task = asyncio.create_task(photos.run())
            await app.run_worker_async(queues=["default"], update_heartbeat_interval=5.0)
    finally:
        if photos is not None:
            photos.stop.set()
        if weather is not None:
            weather.stop.set()
        try:
            if photo_task is not None:
                await photo_task
            elif photos is not None:
                photos.executor.shutdown(wait=True)
        finally:
            try:
                if weather_task is not None:
                    await weather_task
            finally:
                if services is not None:
                    await services.close()
                if database is not None:
                    database.close()


if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(run())
