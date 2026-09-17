"""Train and export the all-crop detector when the training extra is installed."""

from __future__ import annotations

import argparse
import random
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

try:
    from .check_split import count_crop_images, split_sessions, validate_labels
except ImportError:  # Running this file directly from the vision directory.
    from check_split import count_crop_images, split_sessions, validate_labels  # type: ignore[no-redef]

CLASSES = ["plant", "crop_head_or_fruit", "check_suggested"]
CROPS = ["cabbage", "tomato", "spinach"]


def metric_value(values: Any, index: int) -> float | None:
    try:
        return float(values[index])
    except (IndexError, TypeError, ValueError):
        return None


def class_result(box: Any, index: int) -> dict[str, float | None]:
    try:
        precision, recall, map50, _ = box.class_result(index)
    except (AttributeError, IndexError, TypeError, ValueError):
        return {"precision": None, "recall": None, "map50": None}
    return {
        "precision": metric_value([precision], 0),
        "recall": metric_value([recall], 0),
        "map50": metric_value([map50], 0),
    }


def report_for(
    version: str,
    seed: int,
    epochs: int,
    metrics: dict[str, object],
    train_sessions: list[str],
    test_sessions: list[str],
    class_metrics: dict[str, dict[str, float | None]] | None = None,
    crop_counts: dict[str, int] | None = None,
) -> dict[str, Any]:
    """Return the stable report contract consumed by the mobile/backend work."""
    per_class = class_metrics or {
        class_name: {"precision": None, "recall": None, "map50": None} for class_name in CLASSES
    }
    return {
        "version": version,
        "created_at": datetime.now(UTC).isoformat(),
        "seed": seed,
        "epochs": epochs,
        "metrics": metrics,
        "classes": per_class,
        "crops": {crop: {"images": (crop_counts or {}).get(crop, 0)} for crop in CROPS},
        "train_sessions": sorted(train_sessions),
        "test_sessions": sorted(test_sessions),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument("--data", type=Path, required=True, help="Ultralytics data YAML")
    parser.add_argument("--model", default="yolo11n.pt", help="pretrained detector checkpoint")
    parser.add_argument("--report-dir", type=Path, default=Path("apps/ml-service/vision/reports"))
    parser.add_argument("--runs-dir", type=Path, default=Path("apps/ml-service/vision/runs"))
    parser.add_argument("--seed", type=int, default=42)
    parser.add_argument("--epochs", type=int, default=100)
    parser.add_argument("--imgsz", type=int, default=640)
    parser.add_argument("--train-images", type=Path, required=True)
    parser.add_argument("--test-images", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True, help="image,session_id,crop CSV")
    parser.add_argument("--export", action="store_true", help="export the trained model to TFLite")
    args = parser.parse_args()
    try:
        train_sessions, test_sessions = split_sessions(
            args.train_images, args.test_images, args.manifest
        )
        train_counts = validate_labels(args.train_images)
        test_counts = validate_labels(args.test_images)
        crop_counts = count_crop_images(args.train_images, args.test_images, args.manifest)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    if not train_sessions or not test_sessions:
        parser.error("train and test must contain at least one filming session")
    if train_sessions & test_sessions:
        parser.error("train and test session lists overlap")
    if any(count < 300 for count in crop_counts.values()):
        parser.error("the dataset must contain at least 300 images per crop")
    if any(train_counts[class_id] + test_counts[class_id] == 0 for class_id in range(3)):
        parser.error("the dataset must contain at least one labelled image for each class")
    random.seed(args.seed)
    try:
        from ultralytics import YOLO
    except ImportError:
        parser.error("install the pinned training dependencies (ultralytics) before training")
    model = YOLO(args.model)
    result = model.train(
        data=str(args.data),
        epochs=args.epochs,
        seed=args.seed,
        imgsz=args.imgsz,
        project=str(args.runs_dir),
        name=args.version,
    )
    validation = model.val(data=str(args.data), imgsz=args.imgsz, split="test")
    box = getattr(validation, "box", None)
    class_metrics = {
        class_name: class_result(box, index) for index, class_name in enumerate(CLASSES)
    }
    if args.export:
        model.export(format="tflite")
    report = report_for(
        args.version,
        args.seed,
        args.epochs,
        getattr(validation, "results_dict", getattr(result, "results_dict", {})),
        sorted(train_sessions),
        sorted(test_sessions),
        class_metrics,
        crop_counts,
    )
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / f"{args.version}.json").write_text(
        json.dumps(report, indent=2, default=str) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
