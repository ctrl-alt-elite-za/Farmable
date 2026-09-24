import ast
import asyncio
import base64
import json
import time
from collections.abc import AsyncIterator
from pathlib import Path
from urllib.parse import parse_qs, urlsplit

import httpx
import pytest
from farmable_backend.integrations.base import Adapter
from farmable_backend.integrations.fakes import example_audio, examples
from farmable_backend.integrations.gemini import Gemini, has_visible_text
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import SERVICES, TIMEOUTS, ServiceSettings
from farmable_backend.integrations.smoke import check_services, diagnosis_matches, main
from farmable_backend.integrations.turnstile import Turnstile
from farmable_backend.main import create_app
from pydantic import SecretStr, ValidationError

PHONE = "+27820000000"  # Synthetic: only used with the isolated fake / MockTransport.


def test_twilio_sdk_and_literal_hosts_stay_inside_integrations():
    root = Path(__file__).resolve().parents[1] / "src/farmable_backend"
    violations = []
    for path in root.rglob("*.py"):
        relative = path.relative_to(root)
        if relative.parts[0] == "integrations":
            continue
        for node in ast.walk(ast.parse(path.read_text(encoding="utf-8"))):
            modules = []
            if isinstance(node, ast.Import):
                modules = [alias.name for alias in node.names]
            elif isinstance(node, ast.ImportFrom):
                modules = [node.module or ""]
            sdk_import = any(name == "twilio" or name.startswith("twilio.") for name in modules)
            host = ""
            if isinstance(node, ast.Constant) and isinstance(node.value, str):
                value = node.value.strip()
                try:
                    host = urlsplit(value if "://" in value else "//" + value).hostname or ""
                except ValueError:
                    pass  # Non-URL source literals are not provider hostnames.
            provider_host = host == "twilio.com" or host.endswith(".twilio.com")
            if sdk_import or provider_host:
                violations.append(f"{relative}:{node.lineno}")
    assert not violations, "Twilio provider access outside integrations: " + ", ".join(violations)


async def no_wait(delay: float) -> None:
    pass


def fake_settings(**kwargs) -> ServiceSettings:
    return ServiceSettings(environment="ci", integrations_mode="fake", **kwargs)


def fast(registry: ServiceRegistry) -> None:
    for adapter in registry.adapters.values():
        adapter.sleep = no_wait
        adapter.jitter = lambda: 0


async def invoke(registry: ServiceRegistry, service: str):
    calls = {
        "twilio": lambda: registry.twilio.verify(PHONE),
        "turnstile": lambda: registry.turnstile.validate("fixture-token"),
        "azure_stt": lambda: registry.azure_stt.recognize(example_audio()),
        "azure_tts": lambda: registry.azure_tts.synthesize("Fixture sentence."),
        "gemini": lambda: registry.gemini.generate({"contents": []}),
        "crop_health": lambda: registry.crop_health.identify(
            [base64.b64encode(b"fixture image").decode()]
        ),
        "soilgrids": lambda: registry.soilgrids.properties(-26.2, 28.0),
        "open_meteo": lambda: registry.open_meteo.forecast(-26.2, 28.0),
        "maps": lambda: registry.maps.geocode("Johannesburg"),
    }
    return await calls[service]()


@pytest.mark.parametrize("service", SERVICES)
@pytest.mark.parametrize("mode", ["success", "error"])
def test_fake_contracts(service, mode):
    async def run():
        registry = ServiceRegistry(fake_settings(), fake_modes={service: mode})
        fast(registry)
        try:
            result = await invoke(registry, service)
            assert result.ok is (mode == "success")
            assert registry.transport.calls[service] == (1 if result.ok else 3)
            if result.ok:
                if service == "azure_tts":
                    assert result.audio == example_audio()
                else:
                    assert result.data == examples()["success"][service]
            else:
                assert result.error == "http" and result.status == 503 and result.data is None
        finally:
            await registry.close()

    asyncio.run(run())


@pytest.mark.parametrize("service", SERVICES)
def test_adapters_timeout(service):
    async def run():
        registry = ServiceRegistry(fake_settings(), fake_modes={service: "slow"})
        fast(registry)
        registry.adapters[service].timeout = 0.003
        try:
            result = await invoke(registry, service)
            assert not result.ok and result.error == "timeout"
            assert registry.transport.calls[service] == 3
            assert registry.adapters[service].failures == 1  # Logical failures, not retry attempts.
        finally:
            await registry.close()

    asyncio.run(run())


def test_timeouts_match_issue():
    assert tuple(TIMEOUTS.values()) == (10, 5, 15, 10, 60, 20, 10, 10, 10)


def test_circuit_breaker_opens():
    async def run():
        registry = ServiceRegistry(fake_settings(), fake_modes={"twilio": "error"})
        fast(registry)
        now = [100.0]
        registry.twilio.clock = lambda: now[0]
        try:
            for _ in range(5):
                assert (await invoke(registry, "twilio")).error == "http"
            before = registry.transport.calls.copy()
            started = time.perf_counter()
            assert (await invoke(registry, "twilio")).error == "unavailable"
            assert time.perf_counter() - started < 0.05
            assert registry.transport.calls == before
            assert (await invoke(registry, "open_meteo")).ok
            now[0] += 29.9
            assert (await invoke(registry, "twilio")).error == "unavailable"
            now[0] += 0.1
            registry.transport.modes["twilio"] = "success"
            assert (await invoke(registry, "twilio")).ok
            assert registry.twilio.failures == 0 and registry.twilio.opened_at is None
            registry.transport.modes["twilio"] = "error"
            assert (await invoke(registry, "twilio")).error == "http"
            assert registry.twilio.failures == 1
        finally:
            await registry.close()

    asyncio.run(run())


def test_half_open_allows_one_probe_and_cancellation_releases_it():
    async def run():
        registry = ServiceRegistry(fake_settings(), fake_modes={"twilio": "slow"})
        registry.twilio.opened_at = 0
        registry.twilio.clock = lambda: 31
        registry.twilio.failures = 5
        try:
            first = asyncio.create_task(invoke(registry, "twilio"))
            await asyncio.sleep(0.005)
            assert registry.transport.calls["twilio"] == 1
            assert (await invoke(registry, "twilio")).error == "unavailable"
            first.cancel()
            with pytest.raises(asyncio.CancelledError):
                await first
            assert registry.twilio.probe_task is None and registry.twilio.failures == 5
            registry.transport.modes["twilio"] = "success"
            assert (await invoke(registry, "twilio")).ok
        finally:
            await registry.close()

    asyncio.run(run())


@pytest.mark.parametrize("service", SERVICES)
@pytest.mark.parametrize("environment", ["production", "development"])
def test_fault_flags_refused_outside_staging(service, environment):
    with pytest.raises(ValidationError, match="Fault flags require"):
        ServiceSettings(environment=environment, **{"fault_" + service: True})


@pytest.mark.parametrize("environment", ["ci", "staging"])
@pytest.mark.parametrize("service", SERVICES)
def test_fault_switch_never_calls_provider(service, environment):
    async def run():
        registry = ServiceRegistry(
            ServiceSettings(
                environment=environment, integrations_mode="fake", **{"fault_" + service: True}
            )
        )
        try:
            assert (await invoke(registry, service)).error == "unavailable"
            assert not registry.transport.calls
        finally:
            await registry.close()

    asyncio.run(run())


def test_fake_and_live_ci_safety():
    with pytest.raises(ValidationError, match="Fake services require"):
        ServiceSettings(environment="production", integrations_mode="fake")
    with pytest.raises(ValueError, match="Live services are forbidden"):
        ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="live"))

    async def run():
        registry = ServiceRegistry(
            ServiceSettings(environment="production", integrations_mode="disabled")
        )
        try:
            assert (await registry.open_meteo.forecast(0, 0)).error == "unavailable"
        finally:
            await registry.close()

    asyncio.run(run())


@pytest.mark.parametrize(
    "failure,attempts", [(401, 1), (400, 1), (429, 3), (503, 3), ("network", 3), ("json", 1)]
)
def test_retry_rules_and_fixed_errors(failure, attempts):
    async def run():
        requests, delays = [], []

        def handler(request):
            requests.append(request)
            if failure == "network":
                raise httpx.ConnectError("private-provider-exception-and-key", request=request)
            if failure == "json":
                return httpx.Response(200, content=b"private-non-json-provider-error")
            return httpx.Response(failure, json={"secret": "private-provider-body"})

        async def sleep(delay):
            delays.append(delay)

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            adapter = Adapter(
                "maps",
                client,
                ServiceSettings(environment="staging", integrations_mode="live"),
                sleep=sleep,
                jitter=lambda: 0.25,
            )
            result = await adapter.call(httpx.Request("GET", "https://fixture.test"))
            assert not result.ok and len(requests) == attempts
            assert delays == ([0.75, 1.25] if attempts == 3 else [])
            assert "private" not in repr(result) and result.data is None

    asyncio.run(run())


def test_provider_request_contracts():
    async def run():
        registry = ServiceRegistry(fake_settings())
        captured = []
        original = registry.transport.handle_async_request

        async def capture(request):
            captured.append(request)
            return await original(request)

        registry.transport.handle_async_request = capture
        try:
            for service in SERVICES:
                assert (await invoke(registry, service)).ok
            by_host = {request.url.host: request for request in captured}
            twilio = by_host["verify.twilio.com"]
            assert twilio.method == "POST" and twilio.headers["authorization"].startswith("Basic ")
            assert parse_qs(twilio.content.decode()) == {"To": [PHONE], "Channel": ["sms"]}
            turnstile = json.loads(by_host["challenges.cloudflare.com"].content)
            assert turnstile["secret"] == "fixture-key"  # noqa: S105 - deliberately synthetic
            assert turnstile["idempotency_key"]
            stt = by_host["fixture.cognitiveservices.azure.com"]
            assert stt.headers["ocp-apim-subscription-key"] == "fixture-key"
            assert stt.url.params["language"] == "en-ZA" and stt.content == example_audio()
            gemini = by_host["generativelanguage.googleapis.com"]
            assert (
                gemini.headers["x-goog-api-key"] == "fixture-key" and "key" not in gemini.url.params
            )
            crop = by_host["crop.kindwise.com"]
            assert (
                crop.url.path == "/api/v1/identification"
                and crop.headers["api-key"] == "fixture-key"
            )
            assert json.loads(crop.content)["similar_images"] is False
            maps = by_host["geocode.googleapis.com"]
            assert maps.headers["x-goog-api-key"] == "fixture-key" and "key" not in maps.url.params
            assert (await registry.twilio.verify(PHONE, "123456")).data["status"] == "approved"
            await registry.azure_tts.synthesize("<script>& hello")
            assert b"&lt;script&gt;&amp; hello" in captured[-1].content
            await registry.maps.geocode("A/B?&")
            assert "A%2FB%3F%26" in str(captured[-1].url)
        finally:
            await registry.close()

    asyncio.run(run())


@pytest.mark.parametrize(
    "response",
    [
        {"success": False, "hostname": "farmable.test", "action": "sign_up"},
        {"success": True, "hostname": "attacker.test", "action": "sign_up"},
        {"success": True, "hostname": "farmable.test", "action": "other"},
        {"success": "true", "hostname": "farmable.test", "action": "sign_up"},
    ],
)
def test_turnstile_requires_boolean_hostname_and_action(response):
    async def run():
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, json=response))
        ) as client:
            adapter = Turnstile("turnstile", client, fake_settings())
            assert (await adapter.validate("fixture-token")).error == "rejected"
            assert adapter.failures == 0  # A rejected user token is not a provider outage.

    asyncio.run(run())


def test_invalid_inputs_never_call_provider():
    async def run():
        registry = ServiceRegistry(fake_settings())
        try:
            results = [
                await registry.twilio.verify("not-a-phone"),
                await registry.turnstile.validate(""),
                await registry.azure_stt.recognize(b"not-a-wav"),
                await registry.azure_tts.synthesize("", voice='bad"attribute'),
                await registry.crop_health.identify(["not base64!"]),
                await registry.soilgrids.properties(float("nan"), 0),
                await registry.open_meteo.forecast(91, 0),
                await registry.maps.geocode(""),
            ]
            assert all(result.error == "invalid_input" for result in results)
            assert not registry.transport.calls
            with pytest.raises(ValueError, match="refuses unknown"):
                await registry.client.get("https://unexpected.test")
        finally:
            await registry.close()

    asyncio.run(run())


class Chunks(httpx.AsyncByteStream):
    def __init__(self, events, delay=0.0):
        self.events, self.delay, self.closed = events, delay, False

    async def __aiter__(self) -> AsyncIterator[bytes]:
        for event in self.events:
            await asyncio.sleep(self.delay)
            yield ("data: " + json.dumps(event) + "\n\n").encode()

    async def aclose(self):
        self.closed = True


def test_gemini_stream_preserves_raw_parts_and_finishes():
    async def run():
        registry = ServiceRegistry(fake_settings())
        try:
            events = [event async for event in registry.gemini.generate_stream({"contents": []})]
            assert len(events) == 3 and events[-1].done and events[-1].ok
            assert not has_visible_text(events[0].data)
            assert (
                events[0].data["candidates"][0]["content"]["parts"][0]["thoughtSignature"]
                == "fixture-only"
            )
            assert has_visible_text(events[1].data)
        finally:
            await registry.close()

    asyncio.run(run())


@pytest.mark.parametrize("visible", [False, True])
def test_stream_first_text_and_total_budgets_close_response(visible):
    async def run():
        payload = {
            "candidates": [{"content": {"parts": [{"text": "text", "thought": not visible}]}}]
        }
        stream = Chunks([payload] * 100, delay=0.003)
        requests = []

        def handler(request):
            requests.append(request)
            return httpx.Response(200, stream=stream)

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            adapter = Gemini("gemini", client, fake_settings(), timeout=0.012, sleep=no_wait)
            events = [
                event async for event in adapter.generate_stream({}, first_text_timeout=0.007)
            ]
            assert events[-1].done and events[-1].error == "timeout"
            assert len(requests) == 1 and stream.closed

    asyncio.run(run())


def test_stream_cancel_releases_half_open_probe():
    async def run():
        stream = Chunks([examples()["success"]["gemini"]] * 3)
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, stream=stream))
        ) as client:
            adapter = Gemini("gemini", client, fake_settings(), clock=lambda: 31)
            adapter.opened_at, adapter.failures = 0, 5
            iterator = adapter.generate_stream({})
            assert (await anext(iterator)).ok
            await iterator.aclose()
            assert stream.closed and adapter.probe_task is None and adapter.failures == 5

    asyncio.run(run())


@pytest.mark.parametrize(
    "payload",
    [{}, {"candidates": None}, {"candidates": [None]}, {"candidates": [{"content": None}]}],
)
def test_malformed_stream_is_failure_not_exception(payload):
    async def run():
        stream = Chunks([payload])
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, stream=stream))
        ) as client:
            adapter = Gemini("gemini", client, fake_settings())
            events = [event async for event in adapter.generate_stream({})]
            assert events[-1].done and events[-1].error == "invalid_response" and stream.closed

    asyncio.run(run())


@pytest.mark.parametrize("service", SERVICES)
def test_fault_degradation_at_application_boundary(settings, service):
    async def run():
        config = fake_settings(**{"fault_" + service: True})
        app = create_app(
            settings, readiness=lambda: {"database": "ok", "worker": "ok"}, service_settings=config
        )
        async with app.router.lifespan_context(app):
            assert (await invoke(app.state.services, service)).error == "unavailable"
            async with httpx.AsyncClient(
                transport=httpx.ASGITransport(app=app), base_url="http://fixture"
            ) as client:
                assert (await client.get("/health/ready")).status_code == 200
            assert not app.state.services.transport.calls
        assert app.state.services.client.is_closed

    asyncio.run(run())


def test_smoke_never_claims_fake_or_unauthorized_live_pass(monkeypatch, capsys):
    monkeypatch.setenv("ENVIRONMENT", "staging")
    monkeypatch.setenv("INTEGRATIONS_MODE", "fake")
    monkeypatch.setenv("GEMINI_API_KEY", "private-fixture-value-not-for-logs")
    assert main(["--live", "--allow-paid"]) == 1
    output = capsys.readouterr().out
    assert "PASS" not in output and "private" not in output
    assert all("FAIL " + service in output for service in SERVICES)
    monkeypatch.setenv("INTEGRATIONS_MODE", "live")
    assert main([]) == 1


def test_crop_coverage_does_not_invent_unsupported_crops():
    tomato = examples()["success"]["crop_health"]
    assert diagnosis_matches(tomato, "tomato")
    assert not diagnosis_matches(tomato, "cabbage")
    assert not diagnosis_matches(tomato, "spinach")


def test_secret_settings_repr_and_validation_hide_keys():
    key = "private-fixture-key-do-not-log"
    settings = ServiceSettings(gemini_api_key=SecretStr(key))
    assert key not in repr(settings)
    with pytest.raises(ValidationError) as error:
        ServiceSettings(gemini_api_key=SecretStr(key), environment="production", fault_gemini=True)
    assert key not in str(error.value)


def test_api_and_worker_refuse_unsafe_flags_at_startup(settings, monkeypatch):
    from farmable_backend import worker

    monkeypatch.setenv("ENVIRONMENT", "production")
    monkeypatch.setenv("INTEGRATIONS_MODE", "disabled")
    monkeypatch.setenv("FAULT_TWILIO", "true")

    def must_not_connect(*args):
        raise AssertionError("Unsafe configuration must be rejected before connecting")

    monkeypatch.setattr(worker, "create_task_app", must_not_connect)

    async def run():
        app = create_app(settings, readiness=lambda: {})
        with pytest.raises(ValidationError, match="Fault flags require"):
            async with app.router.lifespan_context(app):
                pass
        with pytest.raises(ValidationError, match="Fault flags require"):
            await worker.run()

    asyncio.run(run())


def test_stream_retries_only_before_output():
    async def run():
        calls, delays = [], []
        stream = Chunks([examples()["success"]["gemini"]])

        def handler(request):
            calls.append(request)
            return httpx.Response(503) if len(calls) < 3 else httpx.Response(200, stream=stream)

        async def sleep(delay):
            delays.append(delay)

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            adapter = Gemini("gemini", client, fake_settings(), sleep=sleep, jitter=lambda: 0)
            events = [event async for event in adapter.generate_stream({})]
            assert events[-1].done and events[-1].ok and len(calls) == 3 and stream.closed
            assert delays == [0.5, 1]

    asyncio.run(run())


def test_stream_backoff_is_inside_first_text_deadline():
    async def run():
        now, calls = [100.0], []

        def handler(request):
            calls.append(request)
            return httpx.Response(503)

        async def sleep(delay):
            now[0] += delay

        async with httpx.AsyncClient(transport=httpx.MockTransport(handler)) as client:
            adapter = Gemini(
                "gemini",
                client,
                fake_settings(),
                sleep=sleep,
                clock=lambda: now[0],
                jitter=lambda: 0,
            )
            events = [event async for event in adapter.generate_stream({}, first_text_timeout=0.6)]
            assert events[-1].done and events[-1].error == "timeout"
            assert len(calls) == 2

    asyncio.run(run())


def test_buffered_stream_cannot_emit_after_total_deadline():
    async def run():
        now = [0.0]
        payload = examples()["success"]["gemini"]
        body = ("data: " + json.dumps(payload) + "\n\n") * 2
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(lambda _: httpx.Response(200, content=body))
        ) as client:
            adapter = Gemini("gemini", client, fake_settings(), clock=lambda: now[0])
            iterator = adapter.generate_stream({})
            assert (await anext(iterator)).ok
            now[0] = 61
            terminal = await anext(iterator)
            assert terminal.done and terminal.error == "timeout" and not terminal.ok
            await iterator.aclose()

    asyncio.run(run())


def test_smoke_checks_contracts_without_inventing_crop_coverage(tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("SMOKE_PHONE", PHONE)
    monkeypatch.setenv("SMOKE_TURNSTILE_TOKEN", "fixture-token")
    photo = tmp_path / "fixture.jpg"
    photo.write_bytes(b"synthetic photo fixture, not a real account recording")

    async def run():
        registry = ServiceRegistry(fake_settings(), max_attempts=1)
        try:
            assert not await check_services(
                registry,
                allow_sms=True,
                crop_paths={crop: photo for crop in ("cabbage", "spinach", "tomato")},
            )
            assert registry.transport.calls["twilio"] == 1
            assert registry.transport.calls["crop_health"] == 3
            assert all(
                count <= 1
                for service, count in registry.transport.calls.items()
                if service != "crop_health"
            )
        finally:
            await registry.close()

    asyncio.run(run())
    output = capsys.readouterr().out
    assert "PASS crop_health:tomato" in output
    assert "FAIL crop_health:cabbage" in output and "FAIL crop_health:spinach" in output
    assert PHONE not in output and "fixture-token" not in output
