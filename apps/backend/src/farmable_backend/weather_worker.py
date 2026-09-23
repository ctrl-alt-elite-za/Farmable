"""One bounded asynchronous weather slot in the existing worker process."""

import asyncio
import hashlib
import json
import logging
import time

from farmable_backend.weather_jobs import WeatherJobs
from farmable_backend.weather_policy import calculate, parse_daily, request_period

logger = logging.getLogger(__name__)


class WeatherWorker:
    def __init__(self, sessions, provider):
        kind = "synthetic" if provider.settings.integrations_mode == "fake" else "historical"
        self.jobs = WeatherJobs(sessions, kind)
        self.provider = provider
        self.stop = asyncio.Event()
        self.scan_after = None
        self.next_scan = 0.0

    async def once(self):
        claimed = await asyncio.to_thread(self.jobs.claim)
        if claimed is None:
            return False
        try:
            start, end = request_period(claimed.first_year, claimed.last_year)
            response = await self.provider.history(
                claimed.latitude_tenths, claimed.longitude_tenths, start, end
            )
            if not response.ok or response.data is None:
                raise ValueError("weather_unavailable")
            daily = parse_daily(response.data, start, end)
            rows = await asyncio.to_thread(calculate, daily, claimed.first_year, claimed.last_year)
            digest = hashlib.sha256(
                json.dumps(
                    response.data, sort_keys=True, separators=(",", ":"), allow_nan=False
                ).encode()
            ).hexdigest()
            await asyncio.to_thread(self.jobs.finish, claimed, rows, digest)
        except Exception:
            # Never log provider URLs, raw response data, identifiers or exception text.
            logger.warning("Weather climatology deferred")
            await asyncio.to_thread(self.jobs.fail, claimed)
        return True

    async def run(self):
        while not self.stop.is_set():
            try:
                if time.monotonic() >= self.next_scan:
                    self.scan_after = await asyncio.to_thread(
                        self.jobs.enqueue_existing, self.scan_after
                    )
                    if self.scan_after is None:
                        self.next_scan = time.monotonic() + 3600
                worked = await self.once()
            except Exception:
                logger.error("Weather queue unavailable")
                worked = False
            try:
                await asyncio.wait_for(self.stop.wait(), timeout=1 if worked else 5)
            except TimeoutError:
                pass
