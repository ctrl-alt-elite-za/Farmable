"""Validate fixture evidence and select an offline detector release.

The exporter manifest remains immutable and unmeasured. This module creates a
separate ``*.release.json`` only when both physical-device reports and a
functional fixture report are present and internally consistent.
"""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
from typing import Any

try:
    from vision.benchmark import validate_report
except ModuleNotFoundError:  # Direct ``python vision/release.py`` invocation.
    from benchmark import validate_report  # type: ignore[no-redef]

REQUIRED_CROPS = ("cabbage", "tomato", "spinach")
USABLE = "usable"
RAW_LABEL_TO_CROP = {
    "cabbage plant": "cabbage",
    "cabbage head": "cabbage",
    "tomato plant": "tomato",
    "tomato fruit": "tomato",
    "spinach plant": "spinach",
}


def _read_json(path: Path) -> dict[str, Any]:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise ValueError(f"JSON report {path} must contain an object")
    return value


def validate_fixture_report(report: dict[str, Any]) -> dict[str, Any]:
    """Validate the honest, qualitative fixture-result contract."""
    required = (
        "model_version",
        "fixtures",
        "required_crop_hits",
        "negative_false_positives",
        "results",
    )
    missing = [field for field in required if field not in report]
    if missing:
        raise ValueError(f"fixture report missing fields: {', '.join(missing)}")
    if not isinstance(report["model_version"], str) or not report["model_version"].strip():
        raise ValueError("fixture model_version must be a non-empty string")
    if (
        not isinstance(report["fixtures"], int)
        or isinstance(report["fixtures"], bool)
        or report["fixtures"] <= 0
    ):
        raise ValueError("fixtures must be an integer greater than zero")
    hits = report["required_crop_hits"]
    if not isinstance(hits, dict):
        raise ValueError("required_crop_hits must be an object")
    missing_crops = [crop for crop in REQUIRED_CROPS if crop not in hits]
    if missing_crops:
        raise ValueError(f"required_crop_hits missing: {', '.join(missing_crops)}")
    for crop in REQUIRED_CROPS:
        if hits[crop] not in {"usable", "not_usable"}:
            raise ValueError(f"required_crop_hits.{crop} must be usable or not_usable")
    false_positives = report["negative_false_positives"]
    if (
        not isinstance(false_positives, int)
        or isinstance(false_positives, bool)
        or false_positives < 0
    ):
        raise ValueError("negative_false_positives must be a non-negative integer")
    results = report["results"]
    if not isinstance(results, list) or len(results) != report["fixtures"]:
        raise ValueError("results must contain one result for every fixture")
    for result in results:
        if not isinstance(result, dict):
            raise ValueError("each fixture result must be an object")
        for field in ("fixture_id", "expected_crop", "detected", "false_positive"):
            if field not in result:
                raise ValueError(f"fixture result missing {field}")
        if not isinstance(result["fixture_id"], str) or not result["fixture_id"].strip():
            raise ValueError("fixture_id must be a non-empty string")
        if not isinstance(result["detected"], bool) or not isinstance(
            result["false_positive"], bool
        ):
            raise ValueError("detected and false_positive must be booleans")
        expected_crop = result["expected_crop"]
        if expected_crop is not None and expected_crop not in REQUIRED_CROPS:
            raise ValueError("expected_crop must be cabbage, tomato, spinach or null")
        label = result.get("raw_label")
        if label is not None and label not in RAW_LABEL_TO_CROP:
            raise ValueError("raw_label must be a configured prompt or null")
        confidence = result.get("confidence")
        if confidence is not None and (
            not isinstance(confidence, int | float)
            or isinstance(confidence, bool)
            or not math.isfinite(float(confidence))
            or not 0 <= float(confidence) <= 1
        ):
            raise ValueError("confidence must be a finite number between 0 and 1")
        if result["detected"] and (label is None or confidence is None):
            raise ValueError("detected fixtures require raw_label and confidence")
        if expected_crop is not None and result["false_positive"]:
            raise ValueError("crop fixtures cannot be marked false_positive")
    for crop in REQUIRED_CROPS:
        usable_evidence = any(
            result["expected_crop"] == crop
            and result["detected"]
            and RAW_LABEL_TO_CROP.get(result.get("raw_label")) == crop
            for result in results
        )
        if hits[crop] == USABLE and not usable_evidence:
            raise ValueError(f"required_crop_hits.{crop} has no matching detected fixture")
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
    if ios_report["model_version"] != version or android_report["model_version"] != version:
        raise ValueError("benchmark model_version must match manifest version")
    if fixture_report["model_version"] != version:
        raise ValueError("fixture model_version must match manifest version")
    if any(fixture_report["required_crop_hits"][crop] != USABLE for crop in REQUIRED_CROPS):
        raise ValueError("all required crop fixtures must be usable before selection")
    artifacts = manifest.get("artifacts")
    if not isinstance(artifacts, dict):
        raise ValueError("manifest artifacts are required")
    for report, artifact_name in ((ios_report, "coreml"), (android_report, "tflite")):
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
    selected = dict(manifest)
    selected["measured"] = True
    selected["selected_for_demo"] = True
    selected["benchmarks"] = {"ios": ios_report_path, "android": android_report_path}
    selected["fixture_report"] = fixture_report_path
    return selected


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--ios-report", type=Path, required=True)
    parser.add_argument("--android-report", type=Path, required=True)
    parser.add_argument("--fixtures", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    output = args.output.resolve()
    inputs = (args.manifest, args.ios_report, args.android_report, args.fixtures)
    if output in {path.resolve() for path in inputs}:
        parser.error("--output must not overwrite an input report or export manifest")
    if args.output.exists():
        parser.error(f"release output already exists: {args.output}")
    try:
        selected = select_release(
            _read_json(args.manifest),
            _read_json(args.ios_report),
            _read_json(args.android_report),
            load_fixture_report(args.fixtures),
            ios_report_path=args.ios_report.as_posix(),
            android_report_path=args.android_report.as_posix(),
            fixture_report_path=args.fixtures.as_posix(),
        )
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(selected, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: selected measured release {selected['version']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
