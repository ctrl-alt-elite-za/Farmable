"""Satellite map tiles and their attribution, for signed-in farmers only.

A map screen asks for dozens of tiles at once, so a signed-in token is checked
against the database once and then remembered for a minute; concurrent tiles
for the same token share that one check. Tiles have their own rate limit (see
middleware.TILE_PATH_PREFIX), so a map cannot starve the rest of the app.
"""

import asyncio
import hashlib
import time
from collections.abc import Callable
from typing import Annotated
from uuid import UUID

from fastapi import APIRouter, Depends, Path, Query, Request, Response

from farmable_backend.integrations.map_tiles import MapTiles, TilesUnavailable
from farmable_backend.record_access import ApiError, authenticate
from farmable_backend.records_api import bearer, runtime, token
from farmable_backend.schemas import ErrorResponse, StrictModel

AUTH_TTL_SECONDS = 60
MAX_ZOOM = 22


class TileAuth:
    """Remembers which access tokens were valid, briefly, by digest only."""

    def __init__(self, clock: Callable[[], float] = time.monotonic):
        self.clock = clock
        self.valid: dict[str, tuple[float, UUID]] = {}
        self.pending: dict[str, asyncio.Future[UUID]] = {}

    async def owner(self, request: Request) -> UUID:
        authorization = token(request)
        digest = hashlib.sha256(authorization.encode()).hexdigest() if authorization else ""
        now = self.clock()
        cached = self.valid.get(digest)
        if cached and now < cached[0]:
            return cached[1]
        if digest in self.pending:
            return await asyncio.shield(self.pending[digest])
        future: asyncio.Future[UUID] = asyncio.get_running_loop().create_future()
        self.pending[digest] = future
        try:
            worker = runtime(request)
            owner = await worker.call(_check, worker.service.sessions, authorization)
            if len(self.valid) > 10_000:
                self.valid = {k: v for k, v in self.valid.items() if now < v[0]}
            self.valid[digest] = (now + AUTH_TTL_SECONDS, owner)
            future.set_result(owner)
            return owner
        except BaseException as error:
            future.set_exception(error)
            future.exception()  # Mark retrieved: waiters re-raise it themselves.
            raise
        finally:
            del self.pending[digest]


def _check(sessions, authorization: str | None) -> UUID:
    with sessions() as session:
        return authenticate(session, authorization)


def tiles(request: Request) -> MapTiles:
    return request.app.state.services.map_tiles


def tile_auth(request: Request) -> TileAuth:
    return request.app.state.tile_auth


router = APIRouter(
    dependencies=[Depends(bearer)],
    responses={status: {"model": ErrorResponse} for status in (401, 404, 429, 503)},
)


def _unavailable(error: TilesUnavailable) -> ApiError:
    if error.reason == "disabled":
        return ApiError(503, "maps_disabled")
    if error.reason == "rate_limited":
        return ApiError(429, "maps_rate_limited", 5)
    return ApiError(503, "maps_unavailable", 5)


@router.get(
    "/maps/tiles/{z}/{x}/{y}",
    operation_id="getMapTile",
    response_class=Response,
    responses={200: {"content": {"image/jpeg": {}, "image/png": {}}}},
)
async def map_tile(
    request: Request,
    z: Annotated[int, Path(ge=0, le=MAX_ZOOM)],
    x: Annotated[int, Path(ge=0)],
    y: Annotated[int, Path(ge=0)],
) -> Response:
    if x >= 2**z or y >= 2**z or request.query_params:
        raise ApiError(422, "validation_error")
    await tile_auth(request).owner(request)
    try:
        tile = await tiles(request).tile(z, x, y)
    except TilesUnavailable as error:
        raise _unavailable(error) from None
    if tile is None:
        raise ApiError(404, "no_imagery")
    return Response(
        tile.body,
        media_type=tile.content_type,
        # Only this phone may keep it: the tile came through a signed-in request.
        headers={"Cache-Control": _private(tile.cache_control)},
    )


def _private(cache_control: str | None) -> str:
    for part in (cache_control or "").split(","):
        name, _, value = part.strip().partition("=")
        if name.lower() == "max-age" and value.isdigit():
            return f"private, max-age={min(int(value), 7 * 86400)}"
    return "private, max-age=86400"


class MapAttribution(StrictModel):
    copyright: str


@router.get("/maps/attribution", response_model=MapAttribution, operation_id="getMapAttribution")
async def map_attribution(
    request: Request,
    zoom: Annotated[int, Query(ge=0, le=MAX_ZOOM)],
    north: Annotated[float, Query(ge=-90, le=90)],
    south: Annotated[float, Query(ge=-90, le=90)],
    east: Annotated[float, Query(ge=-180, le=180)],
    west: Annotated[float, Query(ge=-180, le=180)],
) -> MapAttribution:
    if south > north:
        raise ApiError(422, "validation_error")
    await tile_auth(request).owner(request)
    try:
        text = await tiles(request).attribution(zoom, north, south, east, west)
    except TilesUnavailable as error:
        raise _unavailable(error) from None
    return MapAttribution(copyright=text)
