"""Record a physical-device detector benchmark and enforce the iPhone target."""

from __future__ import annotations

import argparse
import json
import math
from datetime import UTC, datetime
from pathlib import Path


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--platform", choices=["ios", "android"], required=True)
    parser.add_argument("--device", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--detector-ms", type=float, required=True, help="measured median latency")
    parser.add_argument(
        "--measurement-source",
        choices=["physical_device"],
        required=True,
        help="benchmark must be measured on the named physical device",
    )
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if not math.isfinite(args.detector_ms) or args.detector_ms <= 0:
        parser.error("--detector-ms must be a finite measured value greater than zero")
    report = {
        "created_at": datetime.now(UTC).isoformat(),
        "platform": args.platform,
        "device": args.device,
        "model": args.model,
        "detector_ms": args.detector_ms,
        "measurement_source": args.measurement_source,
        "passes_target": args.platform != "ios" or args.detector_ms <= 20,
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")
    if not report["passes_target"]:
        print("FAIL: iPhone detector latency exceeds 20 ms")
        return 1
    print(f"PASS: {args.platform} {args.device} detector latency {args.detector_ms:.2f} ms")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
