"""Export the fixed-prompt YOLOE demo detector to Core ML and TFLite.

The prompts are zero-shot: no accuracy report measures this artifact, and the
manifest says so. The trained, report-backed detector replaces it once the
labelled dataset exists.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import shutil
import tempfile
from pathlib import Path
from typing import Any

PROMPTS = ["cabbage plant", "cabbage head", "tomato plant", "tomato fruit", "spinach plant"]
SUFFIXES = {"coreml": ".mlpackage", "tflite": ".tflite"}
IMAGE_SIZE = 640
DEFAULT_MODEL = "yoloe-26n-seg.pt"

# These values describe the reproducible software/model source used by the
# demo path.  The model download itself is performed by Ultralytics, so the
# exporter also accepts explicit values for a release artifact's provenance.
# In particular, this is not a claim that the package version is a model
# checkpoint revision.
DEFAULT_SOURCE_REVISION = "Ultralytics assets release v8.4.0; exporter ultralytics==8.4.0"
DEFAULT_SOURCE_URL = (
    "https://github.com/ultralytics/assets/releases/download/v8.4.0/yoloe-26n-seg.pt"
)
DEFAULT_LICENSE = "AGPL-3.0-only OR Ultralytics Enterprise License"
VERSION_RE = re.compile(r"^[A-Za-z0-9][A-Za-z0-9._-]*$")

RUNTIME_CONTRACT = {
    "input": {
        "size": [IMAGE_SIZE, IMAGE_SIZE],
        "color_order": "RGB",
        "normalization": "divide_by_255",
        "resize": "letterbox",
    },
    "artifact_output": {
        "tensor_shapes": "inspect_generated_artifact",
        "nms": "inspect_generated_artifact",
        "segmentation_masks": "inspect_generated_artifact",
    },
    "application_handoff": {
        "box_coordinates": "normalized_xyxy",
        "class_mapping": {
            "cabbage plant": "cabbage",
            "cabbage head": "cabbage",
            "tomato plant": "tomato",
            "tomato fruit": "tomato",
            "spinach plant": "spinach",
        },
    },
}


def sha256(path: Path) -> str:
    """Return a byte SHA-256 for files and a stable tree digest for packages."""
    if not path.exists():
        raise ValueError(f"artifact does not exist: {path}")
    digest = hashlib.sha256()
    if path.is_file():
        with path.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
        return digest.hexdigest()

    # Core ML exports are directory packages. Include unambiguous relative
    # names and byte lengths, but not the caller-selected package directory
    # name, so an identical package has the same content identity everywhere.
    entries = list(path.rglob("*"))
    symlink = next((entry for entry in entries if entry.is_symlink()), None)
    if symlink is not None:
        raise ValueError(f"artifact packages cannot contain symlinks: {symlink}")
    files = sorted(entry for entry in entries if entry.is_file())
    for file in files:
        relative_name = file.relative_to(path).as_posix().encode()
        digest.update(len(relative_name).to_bytes(8, "big"))
        digest.update(relative_name)
        digest.update(file.stat().st_size.to_bytes(8, "big"))
        with file.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    return digest.hexdigest()


def artifact_bytes(path: Path) -> int:
    """Return the payload byte size for a file or package directory."""
    if path.is_file():
        return path.stat().st_size
    return sum(file.stat().st_size for file in path.rglob("*") if file.is_file())


def export_options(export_format: str, int8: bool, data: str | None) -> dict[str, Any]:
    # FP16 needs no calibration and runs natively on the Neural Engine and mobile GPUs.
    options: dict[str, Any] = {"format": export_format, "imgsz": IMAGE_SIZE}
    if int8:
        options.update(int8=True, data=data)
    else:
        options["half"] = True
    return options


def _remove_artifact(path: Path) -> None:
    if path.is_dir():
        shutil.rmtree(path)
    else:
        path.unlink(missing_ok=True)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--version", required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("apps/ml-service/vision/models"))
    parser.add_argument("--formats", nargs="+", choices=list(SUFFIXES), default=list(SUFFIXES))
    parser.add_argument("--int8", action="store_true", help="int8 instead of FP16")
    parser.add_argument(
        "--data", type=Path, help="dataset YAML of crop images for int8 calibration"
    )
    parser.add_argument("--source-revision", default=DEFAULT_SOURCE_REVISION)
    parser.add_argument("--source-url", default=DEFAULT_SOURCE_URL)
    parser.add_argument("--license", dest="license_name", default=DEFAULT_LICENSE)
    args = parser.parse_args()
    if not VERSION_RE.fullmatch(args.version) or args.version in {".", ".."}:
        parser.error("--version must be a safe filename component")
    if args.int8 and not args.data:
        parser.error("--int8 needs --data with crop calibration images (default is COCO)")
    if args.int8 and not args.data.is_file():
        parser.error(f"--data calibration file does not exist: {args.data}")
    if args.data and not args.int8:
        parser.error("--data is only valid with --int8")
    if args.model != DEFAULT_MODEL and (
        args.source_revision == DEFAULT_SOURCE_REVISION
        or args.source_url == DEFAULT_SOURCE_URL
        or args.license_name == DEFAULT_LICENSE
    ):
        parser.error(
            "a custom --model requires explicit --source-revision, --source-url and --license"
        )
    destinations = {fmt: args.output_dir / f"{args.version}{SUFFIXES[fmt]}" for fmt in args.formats}
    version_manifest = args.output_dir / f"{args.version}.json"
    existing = [str(path) for path in (*destinations.values(), version_manifest) if path.exists()]
    if existing:
        parser.error(f"version {args.version!r} already exported: {', '.join(existing)}")
    try:
        from ultralytics import YOLOE
    except ImportError:
        parser.error("install the pinned YOLOE environment before exporting")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model = YOLOE(args.model)
    source_path = Path(args.model)
    if not source_path.is_file():
        checkpoint_path = getattr(model, "ckpt_path", None)
        if checkpoint_path:
            source_path = Path(str(checkpoint_path))
    if not source_path.is_file():
        parser.error("could not locate the downloaded source checkpoint to hash it")
    model.set_classes(PROMPTS)
    with tempfile.TemporaryDirectory(prefix=f".{args.version}-", dir=args.output_dir) as temporary:
        staging_dir = Path(temporary)
        staged_destinations = {
            export_format: staging_dir / destination.name
            for export_format, destination in destinations.items()
        }
        artifacts: dict[str, dict[str, str | int]] = {}
        for export_format, destination in destinations.items():
            data = str(args.data) if args.data is not None else None
            exported = Path(str(model.export(**export_options(export_format, args.int8, data))))
            staged_destination = staged_destinations[export_format]
            if exported.is_dir():
                shutil.copytree(exported, staged_destination)
            else:
                shutil.copyfile(exported, staged_destination)
            artifacts[export_format] = {
                "path": str(destination),
                "sha256": sha256(staged_destination),
                "bytes": artifact_bytes(staged_destination),
            }
        manifest = {
            "version": args.version,
            "source_model": args.model,
            "source_revision": args.source_revision,
            "source_url": args.source_url,
            "source_sha256": sha256(source_path),
            "license": args.license_name,
            "classes": PROMPTS,
            "input_size": IMAGE_SIZE,
            "precision": "int8" if args.int8 else "fp16",
            "measured": False,
            "runtime_contract": RUNTIME_CONTRACT,
            "artifacts": artifacts,
        }
        staged_manifest = staging_dir / version_manifest.name
        staged_manifest.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

        published: list[Path] = []
        try:
            for export_format, destination in destinations.items():
                staged_destinations[export_format].replace(destination)
                published.append(destination)
            staged_manifest.replace(version_manifest)
            published.append(version_manifest)
        except BaseException:
            for path in reversed(published):
                _remove_artifact(path)
            raise
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
