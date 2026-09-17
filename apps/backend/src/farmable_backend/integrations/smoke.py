"""Explicit staging-only, potentially billable checks. Never log provider data or keys."""

import argparse
import asyncio
import base64
import os
from pathlib import Path
from typing import Any

from pydantic import ValidationError

from farmable_backend.logging import configure_logging

from .azure_stt import valid_wav
from .base import ServiceResult
from .gemini import has_visible_text
from .registry import ServiceRegistry
from .settings import SERVICES, ServiceSettings

CROPS = {
    "cabbage": ("cabbage", "brassica oleracea"),
    "spinach": ("spinach", "spinacia oleracea"),
    "tomato": ("tomato", "solanum lycopersicum"),
}


def diagnosis_matches(data: dict[str, Any], crop: str) -> bool:
    result = data.get("result")
    if data.get("status") != "COMPLETED" or not isinstance(result, dict):
        return False
    plant, disease, identified = (result.get(name) for name in ("is_plant", "disease", "crop"))
    if not isinstance(plant, dict) or plant.get("binary") is not True:
        return False
    suggestions = disease.get("suggestions") if isinstance(disease, dict) else None
    if not isinstance(suggestions, list) or not any(
        isinstance(item, dict)
        and isinstance(item.get("name"), str)
        and item["name"]
        and isinstance(item.get("probability"), int | float)
        for item in suggestions
    ):
        return False
    if not isinstance(identified, dict) or not isinstance(identified.get("suggestions"), list):
        return False
    for suggestion in identified["suggestions"]:
        if not isinstance(suggestion, dict):
            continue
        names = {str(suggestion.get(field, "")).lower() for field in ("name", "scientific_name")}
        probability = suggestion.get("probability")
        if (
            names.intersection(CROPS[crop])
            and isinstance(probability, int | float)
            and probability >= 0.5
        ):
            return True
    return False


def object_value(value: Any) -> dict[str, Any]:
    return value if isinstance(value, dict) else {}


def report(service: str, ok: bool, reason: str = "contract") -> bool:
    # All arguments are fixed service labels / codes, never provider bodies or exception strings.
    print(("PASS " if ok else "FAIL ") + service + ("" if ok else " " + reason))
    return ok


async def check_services(
    registry: ServiceRegistry, *, allow_sms: bool, crop_paths: dict[str, Path | None]
) -> bool:
    passed: list[bool] = []

    def check(result: ServiceResult, valid: bool = True) -> None:
        passed.append(report(result.service, result.ok and valid, result.error or "contract"))

    if allow_sms and os.getenv("SMOKE_PHONE"):
        twilio = await registry.twilio.verify(os.environ["SMOKE_PHONE"])
        check(twilio, (twilio.data or {}).get("status") == "pending")
    else:
        passed.append(report("twilio", False, "sms_not_authorized"))

    settings = registry.turnstile.settings
    turnstile_key = registry.turnstile.secret(settings.turnstile_secret) or ""
    if turnstile_key.startswith(("1x0000", "2x0000", "3x0000")):
        passed.append(report("turnstile", False, "test_key_not_account_proof"))
    else:
        check(await registry.turnstile.validate(os.getenv("SMOKE_TURNSTILE_TOKEN", "")))

    tts = await registry.azure_tts.synthesize("Farmable smoke test.")
    audio = tts.audio or b""
    check(tts, valid_wav(audio))
    if tts.ok and valid_wav(audio):
        stt = await registry.azure_stt.recognize(audio)
        check(
            stt,
            (stt.data or {}).get("RecognitionStatus") == "Success"
            and bool((stt.data or {}).get("DisplayText")),
        )
    else:
        passed.append(report("azure_stt", False, "audio_unavailable"))

    events = [
        event
        async for event in registry.gemini.generate_stream(
            {
                "contents": [
                    {"role": "user", "parts": [{"text": "Reply with: Farmable smoke test."}]}
                ],
                "generationConfig": {"maxOutputTokens": 128},
            }
        )
    ]
    gemini_ok = bool(
        events
        and events[-1].ok
        and events[-1].done
        and any(has_visible_text(event.data or {}) for event in events)
    )
    passed.append(
        report("gemini", gemini_ok, events[-1].error or "contract" if events else "contract")
    )

    crop_checks = []
    for crop, path in crop_paths.items():
        try:
            if path is None:
                raise OSError("Missing smoke image")
            with path.open("rb") as image_file:
                image = image_file.read(4 * 1024 * 1024 + 1)
            if not image or len(image) > 4 * 1024 * 1024:
                raise OSError("Invalid smoke image size")
        except OSError:
            crop_checks.append(report("crop_health:" + crop, False, "image_unavailable"))
            continue
        crop_result = await registry.crop_health.identify([base64.b64encode(image).decode()])
        crop_checks.append(
            report(
                "crop_health:" + crop,
                crop_result.ok and diagnosis_matches(crop_result.data or {}, crop),
                crop_result.error or "coverage_not_proven",
            )
        )
    passed.append(
        report("crop_health", len(crop_checks) == 3 and all(crop_checks), "coverage_not_proven")
    )

    soil = await registry.soilgrids.properties(-26.2, 28.0)
    layers = object_value((soil.data or {}).get("properties")).get("layers")
    check(soil, isinstance(layers, list) and bool(layers))
    weather = await registry.open_meteo.forecast(-26.2, 28.0)
    daily = object_value((weather.data or {}).get("daily"))
    check(
        weather,
        all(
            isinstance(daily.get(field), list) and bool(daily[field])
            for field in ("time", "temperature_2m_max", "precipitation_sum")
        ),
    )
    maps = await registry.maps.geocode("Johannesburg, South Africa")
    results = (maps.data or {}).get("results")
    check(
        maps,
        isinstance(results, list)
        and bool(results)
        and bool(object_value(results[0]).get("location")),
    )
    return all(passed)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true", help="Allow real staging provider calls")
    parser.add_argument(
        "--allow-paid", action="store_true", help="Acknowledge potentially billable calls"
    )
    parser.add_argument("--allow-sms", action="store_true", help="Send SMS to verified SMOKE_PHONE")
    for crop in CROPS:
        parser.add_argument("--" + crop, type=Path, help="Local smoke photo (never committed)")
    args = parser.parse_args(argv)
    configure_logging("error")
    try:
        settings = ServiceSettings()
    except ValidationError:
        for service in SERVICES:
            report(service, False, "invalid_configuration")
        return 1
    if (
        not args.live
        or not args.allow_paid
        or settings.environment != "staging"
        or settings.integrations_mode != "live"
    ):
        for service in SERVICES:
            report(service, False, "live_staging_authorization_required")
        return 1

    async def run() -> bool:
        # One request per check: smoke must not silently multiply SMS/identification charges.
        registry = ServiceRegistry(settings, max_attempts=1)
        try:
            return await check_services(
                registry,
                allow_sms=args.allow_sms,
                crop_paths={crop: getattr(args, crop) for crop in CROPS},
            )
        finally:
            await registry.close()

    try:
        return 0 if asyncio.run(run()) else 1
    except Exception:
        # CLI error boundary: no exception text/traceback can reveal provider input or keys.
        report("smoke", False, "unexpected_error")
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
