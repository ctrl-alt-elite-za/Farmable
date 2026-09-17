import asyncio
import sys

from farmable_backend.config import Settings
from farmable_backend.logging import configure_logging
from farmable_backend.tasks import create_task_app


async def run() -> None:
    settings = Settings()
    configure_logging(settings.log_level)
    app = create_task_app(settings)
    async with app.open_async():
        await app.run_worker_async(queues=["default"], update_heartbeat_interval=5.0)


if __name__ == "__main__":
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(run())
