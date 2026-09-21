import asyncio
import sys

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.gcs_photos import create_gcs_photos
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.logging import configure_logging
from farmable_backend.photo_worker import PhotoWorker
from farmable_backend.tasks import create_task_app


async def run() -> None:
    ServiceSettings()  # Refuse unsafe fault/fake flags before connecting to the queue.
    settings = Settings()
    configure_logging(settings.log_level)
    app = create_task_app(settings)
    database = None
    photos = None
    photo_task = None
    try:
        async with app.open_async():
            if settings.photo_bucket:
                database = Database(settings)
                photos = PhotoWorker(database.sessions, lambda: create_gcs_photos(settings))
                photo_task = asyncio.create_task(photos.run())
            await app.run_worker_async(queues=["default"], update_heartbeat_interval=5.0)
    finally:
        if photos is not None:
            photos.stop.set()
        try:
            if photo_task is not None:
                await photo_task
            elif photos is not None:
                photos.executor.shutdown(wait=True)
        finally:
            if database is not None:
                database.close()


if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(run())
