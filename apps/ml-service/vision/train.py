"""Train and export the all-crop detector when the training extra is installed."""

from __future__ import annotations

import argparse
import hashlib
import json
import random
from datetime import UTC, datetime
from pathlib import Path
from typing import Any

import yaml

try:
    from .check_split import count_crop_images, split_sessions, validate_labels
    from .export import VERSION_RE, artifact_bytes, sha256
except ImportError:  # Running this file directly from the vision directory.
    from check_split import (  # type: ignore[no-redef]
        count_crop_images,
        split_sessions,
        validate_labels,
    )
    from export import VERSION_RE, artifact_bytes, sha256  # type: ignore[no-redef]

CLASSES = ["plant", "crop_head_or_fruit", "check_suggested"]
CROPS = ["cabbage", "tomato", "spinach"]


def metric_value(values: Any, index: int) -> float | None:
    try:
        return float(values[index])
    except (IndexError, TypeError, ValueError):
        return None


def class_result(box: Any, class_id: int) -> dict[str, float | None]:
    try:
        # Metric arrays contain only classes present in the evaluation split.
        index = list(box.ap_class_index).index(class_id)
        precision, recall, map50, _ = box.class_result(index)
    except (AttributeError, IndexError, TypeError, ValueError):
        return {"precision": None, "recall": None, "map50": None}
    return {
        "precision": metric_value([precision], 0),
        "recall": metric_value([recall], 0),
        "map50": metric_value([map50], 0),
    }


def validated_data(data_file: Path, train_images: Path, test_images: Path) -> dict[str, Any]:
    """Bind a local YOLO YAML to the audited directories, without SDK path fallbacks."""
    data = yaml.safe_load(data_file.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("data YAML must contain a mapping")
    names = data.get("names")
    if names not in (CLASSES, dict(enumerate(CLASSES))) or data.get("nc", 3) != 3:
        raise ValueError("data YAML names must match the three ordered Farmable classes")
    root_value = data.get("path", ".")
    if not isinstance(root_value, str):
        raise ValueError("data YAML path must be a directory string")
    # Relative dataset roots are explicitly relative to the source YAML file.
    root = (data_file.resolve().parent / root_value).resolve()
    expected = {"train": train_images.resolve(), "test": test_images.resolve()}
    if "val" not in data and "validation" in data:
        data["val"] = data.pop("validation")
    for split in ("train", "val", "test"):
        value = data.get(split)
        if not isinstance(value, str) or not value:
            raise ValueError(f"data YAML {split} must name one local image directory")
        directory = (root / value).resolve()
        if not directory.is_dir():
            raise ValueError(f"data YAML {split} must name an existing local image directory")
        if split in expected and directory != expected[split]:
            raise ValueError(f"data YAML {split} does not match --{split}-images")
        data[split] = str(directory)
    data["path"] = str(root)
    data["names"] = CLASSES.copy()
    # All directories already exist; the audited snapshot must not run downloads.
    data.pop("download", None)
    return data


def report_for(
    version: str,
    seed: int,
    epochs: int,
    metrics: dict[str, object],
    train_sessions: list[str],
    test_sessions: list[str],
    class_metrics: dict[str, dict[str, float | None]] | None = None,
    crop_counts: dict[str, int] | None = None,
    provenance: dict[str, Any] | None = None,
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
        "provenance": provenance or {},
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", required=True)
    parser.add_argument(
        "--data",
        type=Path,
        required=True,
        help="local YOLO YAML; relative dataset paths are resolved beside this file",
    )
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
    if not VERSION_RE.fullmatch(args.version) or args.version in {".", ".."}:
        parser.error("--version must be a safe filename component")
    try:
        data = validated_data(args.data, args.train_images, args.test_images)
        train_sessions, test_sessions = split_sessions(
            args.train_images, args.test_images, args.manifest
        )
        train_counts = validate_labels(args.train_images)
        test_counts = validate_labels(args.test_images)
        crop_counts = count_crop_images(args.train_images, args.test_images, args.manifest)
    except (OSError, ValueError, yaml.YAMLError) as error:
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
    args.runs_dir.mkdir(parents=True, exist_ok=True)
    audited_data = (args.runs_dir / f"{args.version}.data.yaml").resolve()
    audited_data.write_text(yaml.safe_dump(data), encoding="utf-8")
    model = YOLO(args.model)
    result = model.train(
        data=str(audited_data),
        epochs=args.epochs,
        seed=args.seed,
        imgsz=args.imgsz,
        project=str(args.runs_dir),
        name=args.version,
    )
    validation = model.val(data=str(audited_data), imgsz=args.imgsz, split="test")
    box = getattr(validation, "box", None)
    class_metrics = {
        class_name: class_result(box, index) for index, class_name in enumerate(CLASSES)
    }
    provenance: dict[str, Any] = {
        "manifest_sha256": hashlib.sha256(args.manifest.read_bytes()).hexdigest(),
        "data_yaml_sha256": hashlib.sha256(audited_data.read_bytes()).hexdigest(),
        "source_model": args.model,
        "imgsz": args.imgsz,
        "artifact": None,
    }
    if args.export:
        exported = Path(model.export(format="tflite")).resolve()
        if not exported.is_file() or exported.suffix != ".tflite":
            raise ValueError("TFLite export did not return an existing .tflite file")
        provenance["artifact"] = {
            "format": "tflite",
            "path": str(exported),
            "sha256": sha256(exported),
            "bytes": artifact_bytes(exported),
        }
    report = report_for(
        args.version,
        args.seed,
        args.epochs,
        getattr(validation, "results_dict", getattr(result, "results_dict", {})),
        sorted(train_sessions),
        sorted(test_sessions),
        class_metrics,
        crop_counts,
        provenance,
    )
    args.report_dir.mkdir(parents=True, exist_ok=True)
    (args.report_dir / f"{args.version}.json").write_text(
        json.dumps(report, indent=2, default=str) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
