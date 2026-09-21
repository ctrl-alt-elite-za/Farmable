"""Record repeatable physical-device detector measurements.

This tool records model inference only. Camera capture, frame copies,
tracking, and overlay latency belong to Issue #18. Reports are deliberately
not produced from desktop measurements: ``measurement_source`` is fixed to
``physical_device``.
"""

from __future__ import annotations

import argparse
import json
import math
import re
from collections.abc import Sequence
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
MIN_WARM_SAMPLES = 20


def _positive(value: float, field: str) -> float:
    if isinstance(value, bool) or not isinstance(value, int | float):
        raise ValueError(f"{field} must be a finite value greater than zero")
    if not math.isfinite(value) or value <= 0:
        raise ValueError(f"{field} must be a finite value greater than zero")
    return value


def percentile(samples: Sequence[float], percentile_value: float) -> float:
    """Compute a linear-interpolated percentile from non-empty samples."""
    if not samples:
        raise ValueError("warm samples must not be empty")
    if not 0 <= percentile_value <= 100:
        raise ValueError("percentile must be between 0 and 100")
    ordered = sorted(samples)
    position = (len(ordered) - 1) * percentile_value / 100
    lower = math.floor(position)
    upper = math.ceil(position)
    if lower == upper:
        return ordered[lower]
    return ordered[lower] + (ordered[upper] - ordered[lower]) * (position - lower)


def read_samples(path: Path) -> list[float]:
    """Read a JSON array of warm inference milliseconds."""
    try:
        payload = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"could not read samples JSON: {error}") from error
    if not isinstance(payload, list):
        raise ValueError("samples JSON must be an array of milliseconds")
    samples: list[float] = []
    for value in payload:
        if isinstance(value, bool) or not isinstance(value, int | float):
            raise ValueError("warm sample must be a JSON number")
        samples.append(_positive(float(value), "warm sample"))
    return samples


def validate_report(report: dict[str, Any]) -> dict[str, Any]:
    """Validate the fields required for a physical-device release report."""
    required = (
        "created_at",
        "model_version",
        "artifact_sha256",
        "platform",
        "device",
        "os_version",
        "runtime",
        "precision",
        "input_size",
        "artifact_bytes",
        "cold_load_ms",
        "first_inference_ms",
        "warm_samples",
        "warmup_iterations",
        "peak_memory_mb",
        "measurement_source",
    )
    missing = [field for field in required if field not in report]
    if missing:
        raise ValueError(f"benchmark report missing fields: {', '.join(missing)}")
    created_at = report["created_at"]
    if not isinstance(created_at, str):
        raise ValueError("created_at must be a timezone-aware ISO 8601 timestamp")
    try:
        parsed_created_at = datetime.fromisoformat(created_at)
    except ValueError as error:
        raise ValueError("created_at must be a timezone-aware ISO 8601 timestamp") from error
    if parsed_created_at.utcoffset() is None:
        raise ValueError("created_at must be a timezone-aware ISO 8601 timestamp")
    if not isinstance(report["platform"], str) or report["platform"] not in {
        "ios",
        "android",
    }:
        raise ValueError("platform must be ios or android")
    if not isinstance(report["model_version"], str) or not report["model_version"].strip():
        raise ValueError("model_version must be a non-empty string")
    if not isinstance(report["device"], str) or not report["device"].strip():
        raise ValueError("device must be a non-empty string")
    for field in ("os_version", "runtime", "precision"):
        if not isinstance(report[field], str) or not report[field].strip():
            raise ValueError(f"{field} must be a non-empty string")
    if not isinstance(report["artifact_sha256"], str) or not SHA256_RE.fullmatch(
        report["artifact_sha256"]
    ):
        raise ValueError("artifact_sha256 must be a lowercase 64-character SHA-256")
    for field in ("input_size", "artifact_bytes", "warmup_iterations"):
        value = report[field]
        if not isinstance(value, int) or isinstance(value, bool) or value <= 0:
            raise ValueError(f"{field} must be an integer greater than zero")
    for field in ("cold_load_ms", "first_inference_ms", "peak_memory_mb"):
        _positive(report[field], field)
    if report["measurement_source"] != "physical_device":
        raise ValueError("measurement_source must be physical_device")
    samples = report.get("warm_sample_ms")
    if not isinstance(samples, list) or len(samples) < MIN_WARM_SAMPLES:
        raise ValueError(f"warm_sample_ms must contain at least {MIN_WARM_SAMPLES} values")
    if report["warm_samples"] != len(samples):
        raise ValueError("warm_samples must equal the number of warm_sample_ms values")
    checked_samples = [_positive(value, "warm sample") for value in samples]
    if report.get("warm_p50_ms") != percentile(checked_samples, 50):
        raise ValueError("warm_p50_ms does not match warm_sample_ms")
    if report.get("warm_p95_ms") != percentile(checked_samples, 95):
        raise ValueError("warm_p95_ms does not match warm_sample_ms")
    if "thermal_test_duration_minutes" in report:
        _positive(report["thermal_test_duration_minutes"], "thermal_test_duration_minutes")
    return report


def build_report(
    *,
    model_version: str,
    artifact_sha256: str,
    platform: str,
    device: str,
    os_version: str,
    runtime: str,
    precision: str,
    input_size: int,
    artifact_bytes: int,
    cold_load_ms: float,
    first_inference_ms: float,
    warm_sample_ms: Sequence[float],
    warmup_iterations: int,
    peak_memory_mb: float,
    thermal_test_duration_minutes: float | None = None,
    notes: str | None = None,
) -> dict[str, Any]:
    samples = list(warm_sample_ms)
    report: dict[str, Any] = {
        "created_at": datetime.now(UTC).isoformat(),
        "model_version": model_version,
        "artifact_sha256": artifact_sha256,
        "platform": platform,
        "device": device,
        "os_version": os_version,
        "runtime": runtime,
        "precision": precision,
        "input_size": input_size,
        "artifact_bytes": artifact_bytes,
        "cold_load_ms": cold_load_ms,
        "first_inference_ms": first_inference_ms,
        "warm_samples": len(samples),
        "warm_sample_ms": samples,
        "warm_p50_ms": percentile(samples, 50),
        "warm_p95_ms": percentile(samples, 95),
        "warmup_iterations": warmup_iterations,
        "peak_memory_mb": peak_memory_mb,
        "measurement_source": "physical_device",
    }
    if thermal_test_duration_minutes is not None:
        report["thermal_test_duration_minutes"] = _positive(
            float(thermal_test_duration_minutes), "thermal_test_duration_minutes"
        )
    if notes:
        report["notes"] = notes
    return validate_report(report)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["ios", "android"], required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--model-version", "--model", dest="model_version", required=True)
    parser.add_argument("--artifact-sha256", required=True)
    parser.add_argument("--artifact-bytes", type=int, required=True)
    parser.add_argument("--os-version", required=True)
    parser.add_argument("--runtime", required=True)
    parser.add_argument("--precision", required=True)
    parser.add_argument("--input-size", type=int, default=640)
    parser.add_argument("--cold-load-ms", type=float, required=True)
    parser.add_argument("--first-inference-ms", type=float, required=True)
    parser.add_argument("--warm-samples-file", type=Path)
    parser.add_argument(
        "--warm-sample-ms",
        type=float,
        action="append",
        default=[],
        help="repeat for each measured warm inference, or use --warm-samples-file",
    )
    parser.add_argument("--warmup-iterations", type=int, required=True)
    parser.add_argument("--peak-memory-mb", type=float, required=True)
    parser.add_argument("--thermal-test-duration-minutes", type=float)
    parser.add_argument("--notes")
    parser.add_argument(
        "--measurement-source",
        choices=["physical_device"],
        required=True,
        help="explicit attestation that the supplied measurements came from the named device",
    )
    parser.add_argument("--output", type=Path, required=True)
    return parser


def main() -> int:
    parser = _parser()
    args = parser.parse_args()
    if args.output.exists():
        parser.error(f"benchmark output already exists: {args.output}")
    try:
        samples = list(args.warm_sample_ms)
        if args.warm_samples_file:
            samples.extend(read_samples(args.warm_samples_file))
        if not samples:
            raise ValueError("provide --warm-sample-ms or --warm-samples-file")
        report = build_report(
            model_version=args.model_version,
            artifact_sha256=args.artifact_sha256,
            platform=args.platform,
            device=args.device,
            os_version=args.os_version,
            runtime=args.runtime,
            precision=args.precision,
            input_size=args.input_size,
            artifact_bytes=args.artifact_bytes,
            cold_load_ms=args.cold_load_ms,
            first_inference_ms=args.first_inference_ms,
            warm_sample_ms=samples,
            warmup_iterations=args.warmup_iterations,
            peak_memory_mb=args.peak_memory_mb,
            thermal_test_duration_minutes=args.thermal_test_duration_minutes,
            notes=args.notes,
        )
    except ValueError as error:
        parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    print(
        f"PASS: {args.platform} {args.device} warm p50={report['warm_p50_ms']:.2f} ms "
        f"p95={report['warm_p95_ms']:.2f} ms"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
