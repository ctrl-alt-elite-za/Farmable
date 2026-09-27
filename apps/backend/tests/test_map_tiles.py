"""Satellite map tiles through the backend: the Google key never reaches the phone."""

import asyncio
import json

import httpx
import pytest
from farmable_backend.integrations.map_tiles import FAKE_TILE, MapTiles, TilesUnavailable
from farmable_backend.integrations.settings import ServiceSettings
from farmable_backend.middleware import TILES_PER_MINUTE, RateLimiter
from test_records_api import records  # noqa: F401 -- shared authenticated HTTP/ORM fixture

KEY = "server-key-fixture"


def live_tiles(handler, clock=lambda: 1_000.0) -> tuple[MapTiles, list[httpx.Request]]:
    seen: list[httpx.Request] = []

    def record(request: httpx.Request) -> httpx.Response:
        seen.append(request)
        return handler(request)

    settings = ServiceSettings(
        environment="staging", integrations_mode="live", maps_server_api_key=KEY
    )
    client = httpx.AsyncClient(transport=httpx.MockTransport(record))
    return MapTiles(client, settings, clock=clock), seen


def google(tile_status=200, *, sessions=None):
    """Google's createSession, 2dtiles and viewport endpoints."""
    sessions = sessions if sessions is not None else []

    def handle(request: httpx.Request) -> httpx.Response:
        assert request.headers["x-goog-api-key"] == KEY
        assert "key=" not in str(request.url)  # never in a URL, where it gets logged
        if request.url.path == "/v1/createSession":
            body = json.loads(request.content)
            assert body["mapType"] == "satellite" and body["layerTypes"] == ["layerRoadmap"]
            sessions.append(1)
            return httpx.Response(200, json={"session": f"s{len(sessions)}", "expiry": "999999"})
        if request.url.path.startswith("/v1/2dtiles/"):
            status = tile_status(request) if callable(tile_status) else tile_status
            if status != 200:
                return httpx.Response(status)
            return httpx.Response(
                200,
                content=b"\xff\xd8jpeg",
                headers={"content-type": "image/jpeg", "cache-control": "max-age=3600"},
            )
        if request.url.path == "/tile/v1/viewport":
            return httpx.Response(200, json={"copyright": "Imagery ©2026 Google"})
        return httpx.Response(500)

    return handle


def test_a_tile_is_fetched_with_one_shared_session_and_the_key_in_a_header():
    sessions: list[int] = []
    tiles, seen = live_tiles(google(sessions=sessions))

    async def two():
        return await tiles.tile(15, 18_000, 18_500), await tiles.tile(15, 18_001, 18_500)

    first, second = asyncio.run(two())
    assert first is not None and first.body == b"\xff\xd8jpeg"
    assert first.content_type == "image/jpeg"
    assert second is not None
    assert len(sessions) == 1
    assert seen[1].url.params["session"] == "s1"
    assert seen[1].url.path == "/v1/2dtiles/15/18000/18500"


def test_a_tile_without_imagery_is_none_not_a_failure():
    tiles, _ = live_tiles(google(404))
    assert asyncio.run(tiles.tile(21, 1, 1)) is None


def test_an_expired_session_is_renewed_once():
    sessions: list[int] = []
    calls = {"n": 0}

    def first_rejected(_request):
        calls["n"] += 1
        return 401 if calls["n"] == 1 else 200

    tiles, _ = live_tiles(google(first_rejected, sessions=sessions))
    assert asyncio.run(tiles.tile(10, 1, 1)) is not None
    assert len(sessions) == 2


@pytest.mark.parametrize(("status", "reason"), [(429, "rate_limited"), (500, "http")])
def test_provider_errors_are_fixed_reasons(status, reason):
    tiles, _ = live_tiles(google(status))
    with pytest.raises(TilesUnavailable) as raised:
        asyncio.run(tiles.tile(10, 1, 1))
    assert raised.value.reason == reason


def test_without_a_key_tiles_are_disabled_and_nothing_is_sent():
    seen: list[httpx.Request] = []
    settings = ServiceSettings(environment="staging", integrations_mode="live")
    tiles = MapTiles(httpx.AsyncClient(transport=httpx.MockTransport(seen.append)), settings)
    assert not tiles.configured
    with pytest.raises(TilesUnavailable, match="disabled"):
        asyncio.run(tiles.tile(1, 0, 0))
    assert not seen


def test_attribution_is_cached_for_nearby_views():
    tiles, seen = live_tiles(google())

    async def both():
        return (
            await tiles.attribution(15, -26.101, -26.110, 28.051, 28.040),
            await tiles.attribution(15, -26.1011, -26.1101, 28.0511, 28.0401),
        )

    assert asyncio.run(both()) == ("Imagery ©2026 Google", "Imagery ©2026 Google")
    assert sum(r.url.path == "/tile/v1/viewport" for r in seen) == 1


def test_tiles_have_their_own_larger_rate_limit():
    general, tiles = (
        RateLimiter(clock=lambda: 0.0),
        RateLimiter(clock=lambda: 0.0, limit=TILES_PER_MINUTE),
    )
    assert all(general.retry_after("phone") is None for _ in range(120))
    assert general.retry_after("phone") is not None
    assert all(tiles.retry_after("phone") is None for _ in range(TILES_PER_MINUTE))
    assert tiles.retry_after("phone") is not None


def test_a_signed_in_farmer_gets_a_private_cacheable_tile(records):  # noqa: F811
    response = records.client.get("/maps/tiles/3/2/5")
    assert response.status_code == 200
    assert response.content == FAKE_TILE
    assert response.headers["content-type"] == "image/png"
    assert response.headers["cache-control"].startswith("private, max-age=")


def test_a_map_screen_of_tiles_checks_the_session_once(records, monkeypatch):  # noqa: F811
    import farmable_backend.maps_api as maps_api

    checks = {"n": 0}
    original = maps_api._check

    def counted(*args):
        checks["n"] += 1
        return original(*args)

    monkeypatch.setattr(maps_api, "_check", counted)
    for x in range(8):
        assert records.client.get(f"/maps/tiles/4/{x}/3").status_code == 200
    assert checks["n"] == 1


@pytest.mark.parametrize("authorization", [None, "Bearer " + "z" * 43])
def test_tiles_need_a_signed_in_farmer(records, authorization):  # noqa: F811
    records.client.headers.pop("authorization", None)
    headers = {} if authorization is None else {"authorization": authorization}
    response = records.client.get("/maps/tiles/3/2/5", headers=headers)
    assert response.status_code == 401


@pytest.mark.parametrize(
    "path", ["/maps/tiles/3/8/0", "/maps/tiles/23/0/0", "/maps/tiles/3/1/1?x=1"]
)
def test_impossible_tiles_are_refused(records, path):  # noqa: F811
    assert records.client.get(path).status_code == 422


def test_attribution_is_returned_for_the_view(records):  # noqa: F811
    response = records.client.get(
        "/maps/attribution",
        params={"zoom": 15, "north": -26.1, "south": -26.11, "east": 28.05, "west": 28.04},
    )
    assert response.status_code == 200
    assert response.json() == {"copyright": "Fixture imagery"}
