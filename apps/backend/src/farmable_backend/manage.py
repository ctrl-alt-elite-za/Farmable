"""Explicit vendor schema setup and example-job commands; never run by the API."""

import argparse
import asyncio
import sys

from farmable_backend.config import DatabaseSettings
from farmable_backend.logging import configure_logging, request_id
from farmable_backend.tasks import create_task_app


async def apply_queue_schema(app) -> bool:
    """Install Procrastinate's vendor schema unless it is already installed.

    The vendor schema is plain CREATE statements, so a second run fails on the
    first existing type. Every deploy runs this, so it must be a no-op after the
    first. Returns whether the schema was applied.
    """
    # Procrastinate's own probe for its main table, not application-written SQL.
    if await app.job_manager.check_connection_async():
        return False
    # Use the installed vendor schema verbatim, not application-written SQL.
    await app.schema_manager.apply_schema_async()
    return True


async def run(command: str) -> None:
    settings = DatabaseSettings()
    configure_logging(settings.log_level)
    app = create_task_app(settings)
    async with app.open_async():
        if command == "queue-schema":
            applied = await apply_queue_schema(app)
            print("Queue schema applied" if applied else "Queue schema already present")
        else:
            job_id = await app.tasks["example_job"].defer_async(request_id_value=request_id.get())
            print(job_id)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("command", choices=["queue-schema", "example-job"])
    if sys.platform == "win32":
        asyncio.set_event_loop_policy(asyncio.WindowsSelectorEventLoopPolicy())
    asyncio.run(run(parser.parse_args().command))
