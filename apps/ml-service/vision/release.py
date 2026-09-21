"""Validate fixture evidence and select an offline detector release.

The exporter manifest remains immutable and unmeasured. This module creates a
separate ``*.release.json`` only when both physical-device reports and a
functional fixture report are present and internally consistent.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from collections.abc import Collection
from pathlib import Path
from typing import Any

try:
    from vision.benchmark import validate_report
except ModuleNotFoundError:  # Direct ``python vision/release.py`` invocation.
    from benchmark import validate_report  # type: ignore[no-redef]

REQUIRED_CROPS = ("cabbage", "tomato", "spinach")
REQUIRED_PLATFORMS = ("ios", "android")
FIXTURE_SCHEMA_VERSION = 1
MIN_FIXTURE_CONFIDENCE = 0.5
MIN_FIXTURES_PER_CROP = 2
MIN_NEGATIVE_FIXTURES = 2
RAW_LABEL_TO_CROP = {
    "cabbage plant": "cabbage",
    "cabbage head": "cabbage",
    "tomato plant": "tomato",
    "tomato fruit": "tomato",
    "spinach plant": "spinach",
}


def _read_json(path: Path) -> dict[str, Any]:
    return _read_json_with_sha256(path)[0]


def _read_json_with_sha256(path: Path) -> tuple[dict[str, Any], str]:
    try:
        payload = path.read_bytes()
        value = json.loads(payload)
    except (OSError, UnicodeDecodeError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"JSON report {path} must contain an object")
    return value, hashlib.sha256(payload).hexdigest()


def _require_sha256(value: str | None, field: str) -> str:
    if (
        not isinstance(value, str)
        or len(value) != 64
        or any(character not in "0123456789abcdef" for character in value)
    ):
        raise ValueError(f"{field} must be a lowercase SHA-256")
    return value


def _require_exact_fields(
    value: dict[str, Any], required: Collection[str], description: str
) -> None:
    required_fields = set(required)
    missing = sorted(required_fields - value.keys())
    unexpected = sorted(value.keys() - required_fields)
    if missing:
        raise ValueError(f"{description} missing fields: {', '.join(missing)}")
    if unexpected:
        raise ValueError(f"{description} has unexpected fields: {', '.join(unexpected)}")


def validate_fixture_report(report: dict[str, Any]) -> dict[str, Any]:
    """Validate a fixed fixture set and per-artifact result contract."""
    if not isinstance(report, dict):
        raise ValueError("fixture report must be an object")
    _require_exact_fields(
        report,
        ("schema_version", "model_version", "fixture_set", "runs"),
        "fixture report",
    )
    if (
        not isinstance(report["schema_version"], int)
        or isinstance(report["schema_version"], bool)
        or report["schema_version"] != FIXTURE_SCHEMA_VERSION
    ):
        raise ValueError(f"fixture schema_version must be {FIXTURE_SCHEMA_VERSION}")
    if not isinstance(report["model_version"], str) or not report["model_version"].strip():
        raise ValueError("fixture model_version must be a non-empty string")

    fixtures = report["fixture_set"]
    if not isinstance(fixtures, list) or not fixtures:
        raise ValueError("fixture_set must be a non-empty array")
    fixture_ids: set[str] = set()
    fixture_hashes: set[str] = set()
    fixture_crops: dict[str, str | None] = {}
    for fixture in fixtures:
        if not isinstance(fixture, dict):
            raise ValueError("each fixture must be an object")
        _require_exact_fields(
            fixture,
            ("fixture_id", "fixture_sha256", "expected_crop"),
            "fixture",
        )
        fixture_id = fixture["fixture_id"]
        if not isinstance(fixture_id, str) or not fixture_id.strip():
            raise ValueError("fixture_id must be a non-empty string")
        if fixture_id in fixture_ids:
            raise ValueError("fixture_id values must be unique")
        fixture_ids.add(fixture_id)
        fixture_hash = _require_sha256(
            fixture["fixture_sha256"], f"fixture {fixture_id} fixture_sha256"
        )
        if fixture_hash in fixture_hashes:
            raise ValueError("fixture_sha256 values must be unique")
        fixture_hashes.add(fixture_hash)
        expected_crop = fixture["expected_crop"]
        if expected_crop is not None and expected_crop not in REQUIRED_CROPS:
            raise ValueError("expected_crop must be cabbage, tomato, spinach or null")
        fixture_crops[fixture_id] = expected_crop

    for crop in REQUIRED_CROPS:
        fixture_count = sum(expected == crop for expected in fixture_crops.values())
        if fixture_count < MIN_FIXTURES_PER_CROP:
            raise ValueError(f"fixture_set needs at least {MIN_FIXTURES_PER_CROP} {crop} fixtures")
    negative_count = sum(expected is None for expected in fixture_crops.values())
    if negative_count < MIN_NEGATIVE_FIXTURES:
        raise ValueError(f"fixture_set needs at least {MIN_NEGATIVE_FIXTURES} negative fixtures")

    runs = report["runs"]
    if not isinstance(runs, dict) or set(runs) != set(REQUIRED_PLATFORMS):
        raise ValueError("fixture runs must contain exactly ios and android")
    for platform in REQUIRED_PLATFORMS:
        run = runs[platform]
        if not isinstance(run, dict):
            raise ValueError(f"{platform} fixture run must be an object")
        _require_exact_fields(run, ("artifact_sha256", "results"), f"{platform} fixture run")
        _require_sha256(run["artifact_sha256"], f"{platform} fixture artifact_sha256")
        results = run["results"]
        if not isinstance(results, list) or len(results) != len(fixtures):
            raise ValueError(f"{platform} results must contain one result per fixture")
        result_ids: set[str] = set()
        for result in results:
            if not isinstance(result, dict):
                raise ValueError(f"each {platform} fixture result must be an object")
            _require_exact_fields(
                result,
                ("fixture_id", "detected", "raw_label", "confidence"),
                f"{platform} fixture result",
            )
            fixture_id = result["fixture_id"]
            if not isinstance(fixture_id, str) or fixture_id not in fixture_ids:
                raise ValueError(f"{platform} result references an unknown fixture_id")
            if fixture_id in result_ids:
                raise ValueError(f"{platform} fixture result ids must be unique")
            result_ids.add(fixture_id)
            if not isinstance(result["detected"], bool):
                raise ValueError("detected must be a boolean")
            label = result["raw_label"]
            confidence = result["confidence"]
            if result["detected"]:
                if not isinstance(label, str) or label not in RAW_LABEL_TO_CROP:
                    raise ValueError("detected fixtures require a configured raw_label")
                if (
                    not isinstance(confidence, int | float)
                    or isinstance(confidence, bool)
                    or not math.isfinite(float(confidence))
                    or not MIN_FIXTURE_CONFIDENCE <= float(confidence) <= 1
                ):
                    raise ValueError(
                        "detected fixture confidence must be finite and at least "
                        f"{MIN_FIXTURE_CONFIDENCE}"
                    )
            elif label is not None or confidence is not None:
                raise ValueError("undetected fixtures require null raw_label and confidence")
        if result_ids != fixture_ids:
            raise ValueError(f"{platform} results must cover the exact fixture set")
    return report


def load_fixture_report(path: Path) -> dict[str, Any]:
    return validate_fixture_report(_read_json(path))


def select_release(
    manifest: dict[str, Any],
    ios_report: dict[str, Any],
    android_report: dict[str, Any],
    fixture_report: dict[str, Any],
    *,
    ios_report_path: str = "reports/ios.json",
    android_report_path: str = "reports/android.json",
    fixture_report_path: str = "fixtures.json",
    accepted_licenses: Collection[str] = (),
    ios_report_sha256: str | None = None,
    android_report_sha256: str | None = None,
    fixture_report_sha256: str | None = None,
) -> dict[str, Any]:
    """Return a selected release manifest without changing the export manifest."""
    if not isinstance(manifest, dict):
        raise ValueError("export manifest must be an object")
    if manifest.get("measured") is not False:
        raise ValueError("export manifest must remain unmeasured")
    for report, platform in ((ios_report, "ios"), (android_report, "android")):
        validate_report(report)
        if report["platform"] != platform:
            raise ValueError(f"{platform} report has the wrong platform")
    validate_fixture_report(fixture_report)
    version = manifest.get("version")
    if not isinstance(version, str) or not version:
        raise ValueError("manifest version is required")
    if manifest.get("classes") != list(RAW_LABEL_TO_CROP):
        raise ValueError("manifest classes must match the exact configured prompt order")
    source_hash = manifest.get("source_sha256")
    if (
        not isinstance(source_hash, str)
        or len(source_hash) != 64
        or any(character not in "0123456789abcdef" for character in source_hash)
    ):
        raise ValueError("manifest source_sha256 must be a lowercase SHA-256")
    for field in ("source_model", "source_revision", "source_url", "license"):
        if not isinstance(manifest.get(field), str) or not manifest[field].strip():
            raise ValueError(f"manifest {field} is required")
    if manifest["license"] not in accepted_licenses:
        raise ValueError("manifest license is not in the explicitly accepted license allowlist")
    if ios_report["model_version"] != version or android_report["model_version"] != version:
        raise ValueError("benchmark model_version must match manifest version")
    if fixture_report["model_version"] != version:
        raise ValueError("fixture model_version must match manifest version")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, dict):
        raise ValueError("manifest artifacts are required")
    platform_evidence = (
        ("ios", ios_report, "coreml"),
        ("android", android_report, "tflite"),
    )
    for platform, report, artifact_name in platform_evidence:
        artifact = artifacts.get(artifact_name)
        if not isinstance(artifact, dict):
            raise ValueError(f"manifest artifact {artifact_name} is required")
        if artifact.get("sha256") != report["artifact_sha256"]:
            raise ValueError(f"{artifact_name} report hash does not match manifest")
        if artifact.get("bytes") != report["artifact_bytes"]:
            raise ValueError(f"{artifact_name} report size does not match manifest")
        if report["input_size"] != manifest.get("input_size"):
            raise ValueError(f"{artifact_name} report input size does not match manifest")
        if report["precision"] != manifest.get("precision"):
            raise ValueError(f"{artifact_name} report precision does not match manifest")
        fixture_run = fixture_report["runs"][platform]
        if fixture_run["artifact_sha256"] != artifact["sha256"]:
            raise ValueError(f"{platform} fixture artifact hash does not match manifest")

    fixture_crops = {
        fixture["fixture_id"]: fixture["expected_crop"] for fixture in fixture_report["fixture_set"]
    }
    for platform in REQUIRED_PLATFORMS:
        results = fixture_report["runs"][platform]["results"]
        false_positive_ids = [
            result["fixture_id"]
            for result in results
            if fixture_crops[result["fixture_id"]] is None and result["detected"]
        ]
        if false_positive_ids:
            raise ValueError(f"{platform} fixture run contains negative false positives")
        for crop in REQUIRED_CROPS:
            usable_evidence = sum(
                fixture_crops[result["fixture_id"]] == crop
                and result["detected"]
                and RAW_LABEL_TO_CROP[result["raw_label"]] == crop
                for result in results
            )
            if usable_evidence < MIN_FIXTURES_PER_CROP:
                raise ValueError(
                    f"{platform} fixture run needs at least "
                    f"{MIN_FIXTURES_PER_CROP} matching {crop} detections"
                )
    selected = dict(manifest)
    selected["measured"] = True
    selected["evidence_complete"] = True
    selected["benchmarks"] = {
        "ios": {
            "path": ios_report_path,
            "sha256": _require_sha256(ios_report_sha256, "ios_report_sha256"),
        },
        "android": {
            "path": android_report_path,
            "sha256": _require_sha256(android_report_sha256, "android_report_sha256"),
        },
    }
    selected["fixture_report"] = {
        "path": fixture_report_path,
        "sha256": _require_sha256(fixture_report_sha256, "fixture_report_sha256"),
        "schema_version": FIXTURE_SCHEMA_VERSION,
    }
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--ios-report", type=Path, required=True)
    parser.add_argument("--android-report", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument(
        "--accepted-license",
        action="append",
        default=[],
        help="exact reviewed license value; repeat to allow more than one",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    inputs = (args.manifest, args.ios_report, args.android_report, args.fixtures)
    if output in {path.resolve() for path in inputs}:
        parser.error("--output must not overwrite an input report or export manifest")
    if args.output.exists():
        parser.error(f"release output already exists: {args.output}")
    try:
        manifest = _read_json(args.manifest)
        ios_report, ios_report_sha256 = _read_json_with_sha256(args.ios_report)
        android_report, android_report_sha256 = _read_json_with_sha256(args.android_report)
        fixture_report, fixture_report_sha256 = _read_json_with_sha256(args.fixtures)
        selected = select_release(
            manifest,
            ios_report,
            android_report,
            validate_fixture_report(fixture_report),
            ios_report_path=args.ios_report.as_posix(),
            android_report_path=args.android_report.as_posix(),
            fixture_report_path=args.fixtures.as_posix(),
            accepted_licenses=args.accepted_license,
            ios_report_sha256=ios_report_sha256,
            android_report_sha256=android_report_sha256,
            fixture_report_sha256=fixture_report_sha256,
        )
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(selected, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: evidence-complete measured release {selected['version']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
