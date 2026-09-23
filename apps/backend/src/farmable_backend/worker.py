import asyncio
import sys

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.gcs_photos import create_gcs_photos
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.logging import configure_logging
from farmable_backend.photo_worker import PhotoWorker
from farmable_backend.retention import cleanup
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
    retention_task = None
    retention_stop = asyncio.Event()

    async def run_retention() -> None:
        while not retention_stop.is_set():
            if database is not None:
                await asyncio.to_thread(cleanup, database.sessions)
            try:
                await asyncio.wait_for(retention_stop.wait(), timeout=3600)
            except TimeoutError:
                pass

    try:
        async with app.open_async():
            database = Database(settings)
            retention_task = asyncio.create_task(run_retention())
            if database is not None and services_settings.integrations_mode != "disabled":
                services = ServiceRegistry(services_settings)
                weather = WeatherWorker(database.sessions, services.open_meteo)
                weather_task = asyncio.create_task(weather.run())
            if database is not None and settings.photo_bucket:
                photos = PhotoWorker(database.sessions, lambda: create_gcs_photos(settings))
                photo_task = asyncio.create_task(photos.run())
            await app.run_worker_async(queues=["default"], update_heartbeat_interval=5.0)
    finally:
        retention_stop.set()
        if retention_task is not None:
            await retention_task
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
