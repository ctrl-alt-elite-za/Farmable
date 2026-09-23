"""No paid network calls: HTTP fixtures and an in-memory Live wire peer."""

import asyncio
import json
from contextlib import asynccontextmanager
from datetime import UTC, datetime, timedelta

import httpx
import pytest
import smoke_gemini_live as live
from websockets.asyncio.server import serve
from websockets.datastructures import Headers
from websockets.exceptions import InvalidStatus
from websockets.http11 import Response

ACCESS = "a" * 43
TOKEN = "auth_tokens/private-fixture-never-log"  # noqa: S105 - isolated synthetic credential.
SHA = "b" * 40
CONFIG = live.Config("https://fixture.run.app", SHA, ACCESS)
AUDIO = {
    "serverContent": {
        "modelTurn": {
            "parts": [{"inlineData": {"mimeType": "audio/pcm;rate=24000", "data": "AQI="}}]
        },
        "turnComplete": True,
    }
}


def grant(**overrides):
    now = datetime.now(UTC)
    return {
        "credential": TOKEN,
        "model": "models/fixture-live-model",
        "mode": "live",
        "api_version": "v1beta",
        "expires_at": (now + timedelta(minutes=9)).isoformat(),
        "new_session_expires_at": (now + timedelta(seconds=50)).isoformat(),
        **overrides,
    }


class Body(httpx.AsyncByteStream):
    def __init__(self, data):
        self.data = data
        self.closed = False

    async def __aiter__(self):
        yield self.data

    async def aclose(self):
        self.closed = True


class Peer:
    def __init__(self, messages=None):
        self.messages = list(messages if messages is not None else [{"setupComplete": {}}, AUDIO])
        self.sent = []
        self.closed = False
        self.connections = []
        self.requests = []
        self.bodies = []
        self.payload = grant()
        self.status = 200
        self.headers = {"cache-control": "no-store", "pragma": "no-cache"}
        self.health = {"sha": SHA, "database": "ok", "worker": "ok"}

    def http(self, request):
        self.requests.append(request)
        is_health = request.url.path == "/health/ready"
        body = Body(json.dumps(self.health if is_health else self.payload).encode())
        self.bodies.append(body)
        return httpx.Response(200 if is_health else self.status, stream=body, headers=self.headers)

    async def send(self, value):
        self.sent.append(json.loads(value))

    async def recv(self):
        if not self.messages:
            await asyncio.Future()  # Test deadline must terminate a silent peer.
        message = self.messages.pop(0)
        return message if isinstance(message, str | bytes) else json.dumps(message)

    @asynccontextmanager
    async def connect(self, url, **kwargs):
        self.connections.append((url, kwargs))
        try:
            yield self
        finally:
            self.closed = True

    async def run(self):
        await live.smoke(CONFIG, transport=httpx.MockTransport(self.http), connector=self.connect)


def test_mints_once_then_completes_audio_with_locked_setup():
    peer = Peer()
    asyncio.run(peer.run())
    assert [request.method for request in peer.requests] == ["GET", "POST"]
    assert "authorization" not in peer.requests[0].headers
    assert peer.requests[1].headers["authorization"] == "Bearer " + ACCESS
    assert peer.requests[1].content == b""
    url, options = peer.connections[0]
    assert url == live.LIVE_URL and "?" not in url
    assert options["additional_headers"] == {"Authorization": "Token " + TOKEN}
    assert options["proxy"] is None and options["compression"] is None
    assert options["max_size"] == live.MESSAGE_LIMIT and options["max_queue"] == 4
    assert options["logger"].disabled
    assert peer.sent[0] == {
        "setup": {
            "model": "models/fixture-live-model",
            "generationConfig": {"responseModalities": ["AUDIO"]},
            "sessionResumption": {},
        }
    }
    assert peer.sent[1]["clientContent"]["turnComplete"] is True
    assert peer.closed and all(body.closed for body in peer.bodies)
    assert ACCESS not in repr(CONFIG) and TOKEN not in repr(live.credential(grant()))


@pytest.mark.parametrize(
    "updates",
    [
        {"api_url": "http://fixture.run.app"},
        {"api_url": "https://evil.test"},
        {"api_url": "https://fixture.run.app.evil.test"},
        {"api_url": "https://u:p@fixture.run.app"},
        {"api_url": "https://fixture.run.app/?token=secret"},
        {"api_url": "https://fixture.run.app:443"},
        {"api_url": "https://fixture.run.app/voice"},
        {"api_url": "https://fixture.run.app\n"},
        {"expected_sha": "main"},
        {"access_token": "x\r\nHeader: injected"},
    ],
)
def test_rejects_unsafe_configuration(updates):
    with pytest.raises(live.SmokeFailure, match="invalid_configuration"):
        live.Config(
            **{"api_url": CONFIG.api_url, "expected_sha": SHA, "access_token": ACCESS, **updates}
        )


@pytest.mark.parametrize(
    "updates",
    [
        {"mode": "fake"},
        {"api_version": "v1alpha"},
        {"credential": "server-api-key"},
        {"credential": "auth_tokens/x\r\nHeader: injected"},
        {"credential": "auth_tokens/" + "x" * 8193},
        {"model": "models/evil/path"},
        {"expires_at": "invalid"},
        {"new_session_expires_at": "2099-01-01T00:00:00+00:00"},
        {"new_session_expires_at": "2020-01-01T00:00:00+00:00"},
        {"expires_at": "2099-01-01T00:00:00+00:00"},
        {"expires_at": "2026-01-01T00:00:00"},
    ],
)
def test_bad_credentials_never_connect(updates):
    peer = Peer()
    peer.payload.update(updates)
    with pytest.raises(live.SmokeFailure):
        asyncio.run(peer.run())
    assert not peer.connections and len(peer.requests) == 2
    assert all(body.closed for body in peer.bodies)


@pytest.mark.parametrize("status", [301, 302, 307, 308, 401, 403, 429, 500, 503])
def test_http_errors_never_retry_or_follow_redirects(status):
    peer = Peer()
    peer.status = status
    peer.headers["location"] = "https://evil.test"
    with pytest.raises(live.SmokeFailure):
        asyncio.run(peer.run())
    assert len(peer.requests) == 2 and not peer.connections
    assert all(body.closed for body in peer.bodies)


@pytest.mark.parametrize("health", [{"sha": "wrong"}, {"database": "down"}, {"worker": "down"}])
def test_checks_revision_before_sending_session_token(health):
    peer = Peer()
    peer.health.update(health)
    with pytest.raises(live.SmokeFailure, match="revision"):
        asyncio.run(peer.run())
    assert len(peer.requests) == 1 and not peer.connections


@pytest.mark.parametrize(
    "headers",
    [
        {"cache-control": "public"},
        {"pragma": ""},
        {"content-encoding": "gzip"},
    ],
)
def test_refuses_unsafe_response_headers(headers):
    peer = Peer()
    peer.headers.update(headers)
    with pytest.raises(live.SmokeFailure):
        asyncio.run(peer.run())
    assert not peer.connections


def test_http_body_limit():
    peer = Peer()
    peer.payload["untrusted"] = "x" * live.HTTP_LIMIT
    with pytest.raises(live.SmokeFailure, match="http_response_limit"):
        asyncio.run(peer.run())
    assert not peer.connections and all(body.closed for body in peer.bodies)


@pytest.mark.parametrize(
    "messages",
    [
        [{"setupComplete": None}],
        [{"serverContent": {}}],
        [{"setupComplete": {}}, {"serverContent": {"turnComplete": True}}],
        [{"setupComplete": {}}, {"serverContent": {"interrupted": True}}],
        [{"setupComplete": {}}, {"error": {"message": TOKEN}}],
        [{"setupComplete": {}}, {"toolCall": {}}],
        [{"setupComplete": {}}, {"goAway": {}}],
        [{"setupComplete": {}}, "not json"],
        [{"setupComplete": {}}, []],
        [
            {"setupComplete": {}},
            {
                "serverContent": {
                    "modelTurn": {
                        "parts": [
                            {
                                "inlineData": {
                                    "mimeType": "audio/pcm;rate=24000",
                                    "data": "not base64!",
                                }
                            }
                        ]
                    }
                }
            },
        ],
    ],
)
def test_bad_live_response_never_passes_and_closes_socket(messages):
    peer = Peer(messages)
    with pytest.raises((live.SmokeFailure, ValueError)):
        asyncio.run(peer.run())
    assert peer.closed and len(peer.connections) == 1


@pytest.mark.parametrize("phase", ["setup", "turn", "total"])
def test_silent_peer_times_out_and_closes(phase, monkeypatch):
    peer = Peer([] if phase == "setup" else [{"setupComplete": {}}])
    monkeypatch.setattr(live, phase.upper() + "_SECONDS", 0.02)
    with pytest.raises(TimeoutError):
        asyncio.run(peer.run())
    assert peer.closed


@pytest.mark.parametrize("limit", ["MESSAGE_LIMIT", "TOTAL_LIMIT", "MESSAGE_COUNT"])
def test_stream_limits_close_connection(limit, monkeypatch):
    peer = Peer([{"setupComplete": {}}, {"usageMetadata": {"x": "a" * 100}}, AUDIO])
    monkeypatch.setattr(live, limit, 1 if limit == "MESSAGE_COUNT" else 50)
    with pytest.raises(live.SmokeFailure, match="websocket_response_limit"):
        asyncio.run(peer.run())
    assert peer.closed


def test_cancellation_closes_connection():
    peer = Peer([])

    async def run():
        task = asyncio.create_task(peer.run())
        while not peer.connections:
            await asyncio.sleep(0)
        task.cancel()
        with pytest.raises(asyncio.CancelledError):
            await task

    asyncio.run(run())
    assert peer.closed


@pytest.mark.parametrize("status", [301, 302, 303, 307, 308])
def test_websocket_redirect_hook_refuses_all_locations(status):
    error = InvalidStatus(Response(status, "Redirect", Headers({"Location": "wss://evil.test"})))
    connection = live.NoRedirectConnect(live.LIVE_URL)
    assert connection.process_redirect(error) is error


def test_real_websocket_transport_never_follows_redirect():
    async def run():
        hits = []

        async def unused(ws):
            raise AssertionError("A redirect must not establish a WebSocket")

        def redirect(connection, request):
            hits.append(request.path)
            assert request.headers["Authorization"] == "Token " + TOKEN
            return Response(302, "Redirect", Headers({"Location": "/second"}))

        async with serve(unused, "127.0.0.1", 0, process_request=redirect) as server:
            port = server.sockets[0].getsockname()[1]
            with pytest.raises(InvalidStatus):
                async with live.NoRedirectConnect(
                    f"ws://127.0.0.1:{port}/first",
                    proxy=None,
                    additional_headers={"Authorization": "Token " + TOKEN},
                ):
                    raise AssertionError("Must reject the handshake")
        assert hits == ["/first"]

    asyncio.run(run())


def test_real_websocket_transport_completes_local_fixture_turn():
    async def run():
        received = []

        async def handler(ws):
            received.append(json.loads(await ws.recv()))
            await ws.send(json.dumps({"setupComplete": {}}))
            received.append(json.loads(await ws.recv()))
            await ws.send(json.dumps(AUDIO).encode())  # Google also sends binary JSON frames.
            await ws.wait_closed()

        async with serve(handler, "127.0.0.1", 0) as server:
            port = server.sockets[0].getsockname()[1]
            async with live.NoRedirectConnect(
                f"ws://127.0.0.1:{port}",
                proxy=None,
                max_size=live.MESSAGE_LIMIT,
                compression=None,
                close_timeout=2,
            ) as ws:
                await live.audio_turn(ws, live.credential(grant()))
        assert len(received) == 2

    asyncio.run(run())


def enable(monkeypatch):
    for name, value in {
        "ENVIRONMENT": "staging",
        "INTEGRATIONS_MODE": "live",
        "SMOKE_API_URL": CONFIG.api_url,
        "SMOKE_EXPECTED_SHA": SHA,
        "SMOKE_ACCESS_TOKEN": ACCESS,
    }.items():
        monkeypatch.setenv(name, value)
    monkeypatch.delenv("CI", raising=False)
    monkeypatch.delenv("GITHUB_ACTIONS", raising=False)


@pytest.mark.parametrize(
    "env,value",
    [
        ("ENVIRONMENT", "production"),
        ("ENVIRONMENT", "ci"),
        ("INTEGRATIONS_MODE", "fake"),
        ("CI", "true"),
        ("GITHUB_ACTIONS", "true"),
    ],
)
def test_cli_refuses_unauthorized_environments(env, value, monkeypatch, capsys):
    enable(monkeypatch)
    monkeypatch.setenv(env, value)
    assert live.main(["--live", "--allow-paid"]) == 1
    assert capsys.readouterr().out == "FAIL gemini_live live_staging_authorization_required\n"


@pytest.mark.parametrize("args", [[], ["--live"], ["--allow-paid"]])
def test_cli_requires_both_opt_ins(args, monkeypatch, capsys):
    enable(monkeypatch)
    assert live.main(args) == 1
    assert "authorization_required" in capsys.readouterr().out


def test_cli_never_logs_exception_secrets(monkeypatch, capsys):
    enable(monkeypatch)

    async def fail(config):
        raise RuntimeError(ACCESS + TOKEN + " private audio")

    monkeypatch.setattr(live, "smoke", fail)
    assert live.main(["--live", "--allow-paid"]) == 1
    captured = capsys.readouterr()
    assert captured.out == "FAIL gemini_live connection_or_response_failed\n"
    assert captured.err == ""


def test_cli_pass_only_after_completed_exchange(monkeypatch, capsys):
    enable(monkeypatch)
    peer = Peer()
    smoke = live.smoke

    async def run(config):
        await smoke(config, transport=httpx.MockTransport(peer.http), connector=peer.connect)

    monkeypatch.setattr(live, "smoke", run)
    assert live.main(["--live", "--allow-paid"]) == 0
    assert capsys.readouterr().out == "PASS gemini_live audio_turn_completed\n"
    assert peer.closed
