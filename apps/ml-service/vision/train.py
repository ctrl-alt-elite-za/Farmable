"""Train and export the all-crop detector when the training extra is installed."""

from __future__ import annotations

import argparse
import json
import random
from datetime import UTC, datetime
from pathlib import Path

CLASSES = ["plant", "crop_head_or_fruit", "check_suggested"]


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--data", type=Path, required=True, help="Ultralytics data YAML")
    parser.add_argument("--report-dir", type=Path, default=Path("apps/ml-service/vision/reports"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--export", action="store_true", help="export the trained model to TFLite")
    args = parser.parse_args()
    random.seed(args.seed)
    try:
        from ultralytics import YOLO
    except ImportError:
        parser.error("install the pinned training dependencies (ultralytics) before training")
    model = YOLO("yolo11n.pt")
    result = model.train(
        data=str(args.data),
        epochs=args.epochs,
        seed=args.seed,
        project=str(args.report_dir),
        name=args.version,
    )
    if args.export:
        model.export(format="tflite")
    report = {
        "version": args.version,
        "created_at": datetime.now(UTC).isoformat(),
        "seed": args.seed,
        "epochs": args.epochs,
        "metrics": getattr(result, "results_dict", {}),
        "classes": CLASSES,
    }
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / f"{args.version}.json").write_text(
        json.dumps(report, indent=2, default=str) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
