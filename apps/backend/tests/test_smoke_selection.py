"""Selecting a smoke check never authorizes unrelated provider calls."""

import asyncio

import pytest
from farmable_backend.integrations import smoke
from farmable_backend.integrations.fakes import example_audio
from farmable_backend.integrations.registry import ServiceRegistry
from farmable_backend.integrations.settings import SERVICES, ServiceSettings


@pytest.mark.parametrize("selected", SERVICES)
def test_only_selected_provider_is_called(selected, tmp_path, monkeypatch, capsys):
    monkeypatch.setenv("SMOKE_PHONE", "+27820000000")
    monkeypatch.setenv("SMOKE_TURNSTILE_TOKEN", "fixture-token")
    wav = tmp_path / "fixture.wav"
    wav.write_bytes(example_audio())
    photo = tmp_path / "fixture.jpg"
    photo.write_bytes(b"synthetic fixture")

    async def run():
        registry = ServiceRegistry(
            ServiceSettings(environment="ci", integrations_mode="fake"), max_attempts=1
        )
        try:
            result = await smoke.check_services(
                registry,
                allow_sms=True,
                crop_paths=dict.fromkeys(smoke.CROPS, photo),
                services=(selected,),
                stt_wav=wav,
            )
            assert result is (selected != "crop_health")
            assert dict(registry.transport.calls) == {
                selected: 3 if selected == "crop_health" else 1
            }
        finally:
            await registry.close()

    asyncio.run(run())
    lines = capsys.readouterr().out.splitlines()
    assert all(line.split()[1].split(":")[0] == selected for line in lines)


@pytest.mark.parametrize("services", [(), ("unknown",), ("gemini", "gemini")])
def test_bad_selection_makes_no_calls(services):
    async def run():
        registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
        try:
            with pytest.raises(ValueError, match="selection"):
                await smoke.check_services(
                    registry, allow_sms=True, crop_paths={}, services=services
                )
            assert not registry.transport.calls
        finally:
            await registry.close()

    asyncio.run(run())


@pytest.mark.parametrize("selected", ["twilio", "azure_stt", "crop_health"])
def test_missing_inputs_never_call_the_provider(selected, capsys):
    async def run():
        registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
        try:
            assert not await smoke.check_services(
                registry,
                allow_sms=False,
                crop_paths={},
                services=(selected,),
            )
            assert not registry.transport.calls
        finally:
            await registry.close()

    asyncio.run(run())
    assert "FAIL " + selected in capsys.readouterr().out


def test_cli_deduplicates_selection_and_closes_client(monkeypatch, capsys):
    registry = ServiceRegistry(ServiceSettings(environment="ci", integrations_mode="fake"))
    monkeypatch.setenv("ENVIRONMENT", "staging")
    monkeypatch.setenv("INTEGRATIONS_MODE", "live")
    monkeypatch.setattr(smoke, "ServiceRegistry", lambda *a, **kw: registry)
    assert smoke.main(["--live", "--allow-paid", "--service", "gemini", "--service", "gemini"]) == 0
    assert dict(registry.transport.calls) == {"gemini": 1}
    assert registry.client.is_closed
    assert capsys.readouterr().out == "PASS gemini\n"


def test_selection_does_not_bypass_live_authorization(monkeypatch, capsys):
    monkeypatch.setenv("ENVIRONMENT", "staging")
    monkeypatch.setenv("INTEGRATIONS_MODE", "live")

    def refused(*args, **kwargs):
        raise AssertionError("No transport before authorization")

    monkeypatch.setattr(smoke, "ServiceRegistry", refused)
    assert smoke.main(["--service", "gemini"]) == 1
    assert capsys.readouterr().out == "FAIL gemini live_staging_authorization_required\n"
