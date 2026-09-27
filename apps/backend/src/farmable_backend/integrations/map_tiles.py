"""Google Map Tiles (satellite with road and place labels) for the app's maps.

The server key never reaches the phone: the app asks this backend for each tile
and this fetches it from Google with a shared, cached session. A tile Google has
no imagery for is a 404, not a provider failure, so empty hills at high zoom
never trip anything. Never logs a key, session token or coordinates.
"""

import asyncio
import base64
import time
from collections.abc import Callable
from dataclasses import dataclass

import httpx

from .settings import ServiceSettings

API = "https://tile.googleapis.com"
TIMEOUT_SECONDS = 10.0
MAX_TILE_BYTES = 2 * 1024 * 1024
# Renew a little before Google's expiry so an in-flight tile never carries a dead one.
SESSION_MARGIN_SECONDS = 3600
# A 1x1 transparent PNG, for CI's fake mode: no key and no network.
FAKE_TILE = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII="
)


class TilesUnavailable(Exception):
    """Fixed reason codes only; never provider text."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason


@dataclass(frozen=True)
class Tile:
    body: bytes
    content_type: str
    cache_control: str | None


class MapTiles:
    def __init__(
        self,
        client: httpx.AsyncClient,
        settings: ServiceSettings,
        *,
        clock: Callable[[], float] = time.time,
    ):
        self.client, self.settings, self.clock = client, settings, clock
        self._session: str | None = None
        self._expires = 0.0
        self._lock = asyncio.Lock()
        self._attribution: dict[tuple[int, ...], tuple[float, str]] = {}

    @property
    def fake(self) -> bool:
        return self.settings.integrations_mode == "fake"

    @property
    def configured(self) -> bool:
        key = self.settings.maps_server_api_key
        return self.fake or (
            self.settings.integrations_mode == "live"
            and key is not None
            and bool(key.get_secret_value())
        )

    def _headers(self) -> dict[str, str]:
        key = self.settings.maps_server_api_key
        if key is None:  # `configured` is checked first; never send an empty key.
            raise TilesUnavailable("disabled")
        return {"X-Goog-Api-Key": key.get_secret_value()}

    async def _send(self, request: httpx.Request) -> httpx.Response:
        try:
            async with asyncio.timeout(TIMEOUT_SECONDS):
                response = await self.client.send(request)
        except (httpx.HTTPError, TimeoutError):
            raise TilesUnavailable("network") from None
        return response

    async def _session_token(self, *, renew: bool = False) -> str:
        async with self._lock:
            if not renew and self._session and self.clock() < self._expires:
                return self._session
            response = await self._send(
                httpx.Request(
                    "POST",
                    f"{API}/v1/createSession",
                    headers=self._headers(),
                    json={
                        "mapType": "satellite",
                        # Roads and place names over the imagery ("hybrid").
                        "layerTypes": ["layerRoadmap"],
                        "language": "en-ZA",
                        "region": "ZA",
                    },
                )
            )
            if response.status_code != 200:
                raise TilesUnavailable("session")
            try:
                body = response.json()
                token, expiry = str(body["session"]), float(body["expiry"])
            except (ValueError, KeyError, TypeError):
                raise TilesUnavailable("session") from None
            self._session = token
            self._expires = expiry - SESSION_MARGIN_SECONDS
            return token

    async def tile(self, z: int, x: int, y: int) -> Tile | None:
        """The tile's image, or None where Google has no imagery for it."""
        if self.fake:
            return Tile(FAKE_TILE, "image/png", "private, max-age=86400")
        if not self.configured:
            raise TilesUnavailable("disabled")
        for renew in (False, True):
            session = await self._session_token(renew=renew)
            response = await self._send(
                httpx.Request(
                    "GET",
                    f"{API}/v1/2dtiles/{z}/{x}/{y}",
                    params={"session": session},
                    headers=self._headers(),
                )
            )
            if response.status_code == 200:
                if not response.content or len(response.content) > MAX_TILE_BYTES:
                    raise TilesUnavailable("invalid_response")
                content_type = response.headers.get("content-type", "")
                if not content_type.startswith("image/"):
                    raise TilesUnavailable("invalid_response")
                return Tile(response.content, content_type, response.headers.get("cache-control"))
            if response.status_code == 404:
                return None
            # An expired or revoked session: make a new one and try once more.
            if response.status_code in {400, 401, 403} and not renew:
                continue
            if response.status_code == 429:
                raise TilesUnavailable("rate_limited")
            raise TilesUnavailable("http")
        raise TilesUnavailable("session")

    async def attribution(
        self, zoom: int, north: float, south: float, east: float, west: float
    ) -> str:
        """The copyright line Google requires for this view, cached for an hour."""
        if self.fake:
            return "Fixture imagery"
        if not self.configured:
            raise TilesUnavailable("disabled")
        # Rounded so nearby views share an answer instead of each costing a call.
        key = (zoom, *(round(v * 100) for v in (north, south, east, west)))
        cached = self._attribution.get(key)
        if cached and self.clock() < cached[0]:
            return cached[1]
        session = await self._session_token()
        response = await self._send(
            httpx.Request(
                "GET",
                f"{API}/tile/v1/viewport",
                params={
                    "session": session,
                    "zoom": zoom,
                    "north": north,
                    "south": south,
                    "east": east,
                    "west": west,
                },
                headers=self._headers(),
            )
        )
        if response.status_code != 200:
            raise TilesUnavailable("http")
        try:
            text = str(response.json().get("copyright") or "")
        except ValueError:
            raise TilesUnavailable("invalid_response") from None
        if len(self._attribution) > 2000:
            self._attribution.clear()
        self._attribution[key] = (self.clock() + 3600, text)
        return text
