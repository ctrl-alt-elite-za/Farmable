"""Export the fixed-prompt YOLOE demo detector to Core ML and TFLite.

The prompts are zero-shot: no accuracy report measures this artifact, and the
manifest says so. The trained, report-backed detector replaces it once the
labelled dataset exists.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

PROMPTS = ["cabbage plant", "cabbage head", "tomato plant", "tomato fruit", "spinach plant"]
SUFFIXES = {"coreml": ".mlpackage", "tflite": ".tflite"}
IMAGE_SIZE = 640


def sha256(path: Path) -> str:
    """Return a byte SHA-256 for files and a stable tree digest for packages."""
    digest = hashlib.sha256()
    if path.is_file():
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()

    # Core ML exports are directory packages. Include relative names so the
    # manifest detects both changed files and changed package layout.
    files = sorted(p for p in path.rglob("*") if p.is_file())
    for file in files:
        digest.update(file.relative_to(path.parent).as_posix().encode())
        with file.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    return digest.hexdigest()


def export_options(export_format: str, int8: bool, data: str | None) -> dict[str, Any]:
    # FP16 needs no calibration and runs natively on the Neural Engine and mobile GPUs.
    options: dict[str, Any] = {"format": export_format, "imgsz": IMAGE_SIZE}
    if int8:
        options.update(int8=True, data=data)
    else:
        options["half"] = True
    return options


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="yoloe-26n-seg.pt")
    parser.add_argument("--version", required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("apps/ml-service/vision/models"))
    parser.add_argument("--formats", nargs="+", choices=list(SUFFIXES), default=list(SUFFIXES))
    parser.add_argument("--int8", action="store_true", help="int8 instead of FP16")
    parser.add_argument("--data", help="dataset YAML of crop images for int8 calibration")
    args = parser.parse_args()
    if args.int8 and not args.data:
        parser.error("--int8 needs --data with crop calibration images (default is COCO)")
    destinations = {
        fmt: args.output_dir / f"{args.version}{SUFFIXES[fmt]}" for fmt in args.formats
    }
    version_manifest = args.output_dir / f"{args.version}.json"
    existing = [
        str(path) for path in (*destinations.values(), version_manifest) if path.exists()
    ]
    if existing:
        parser.error(f"version {args.version!r} already exported: {', '.join(existing)}")
    try:
        from ultralytics import YOLOE
    except ImportError:
        parser.error("install the pinned YOLOE environment before exporting")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model = YOLOE(args.model)
    model.set_classes(PROMPTS)
    artifacts: dict[str, dict[str, str]] = {}
    for export_format, destination in destinations.items():
        exported = Path(str(model.export(**export_options(export_format, args.int8, args.data))))
        if exported.is_dir():
            shutil.copytree(exported, destination)
        else:
            shutil.copyfile(exported, destination)
        artifacts[export_format] = {"path": str(destination), "sha256": sha256(destination)}
    manifest = {
        "version": args.version,
        "source_model": args.model,
        "classes": PROMPTS,
        "input_size": IMAGE_SIZE,
        "precision": "int8" if args.int8 else "fp16",
        "measured": False,
        "artifacts": artifacts,
    }
    (args.output_dir / f"{args.version}.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
