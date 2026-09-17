"""Bake fixed YOLOE crop prompts into Core ML and LiteRT artifacts."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
from pathlib import Path
from typing import Any

PROMPTS = ["cabbage plant", "cabbage head", "tomato plant", "tomato fruit", "spinach plant"]
FORMATS = {"coreml", "litert"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    files = [path] if path.is_file() else sorted(p for p in path.rglob("*") if p.is_file())
    for file in files:
        digest.update(file.relative_to(path.parent).as_posix().encode())
        with file.open("rb") as handle:
            for block in iter(lambda: handle.read(1024 * 1024), b""):
                digest.update(block)
    return digest.hexdigest()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", default="yoloe-26n-seg.pt")
    parser.add_argument("--version", required=True)
    parser.add_argument("--output-dir", type=Path, default=Path("apps/ml-service/vision/models"))
    parser.add_argument("--formats", nargs="+", choices=sorted(FORMATS), default=sorted(FORMATS))
    args = parser.parse_args()
    try:
        from ultralytics import YOLOE
    except ImportError:
        parser.error("install the pinned YOLOE environment before exporting")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    model = YOLOE(args.model)
    model.set_classes(PROMPTS)
    artifacts: dict[str, dict[str, Any]] = {}
    for export_format in args.formats:
        options: dict[str, Any] = {"format": export_format, "imgsz": 640}
        if export_format == "coreml":
            options["quantize"] = 8
        else:
            options["int8"] = True
        exported = Path(str(model.export(**options)))
        suffix = ".mlpackage" if export_format == "coreml" else ".tflite"
        destination = args.output_dir / f"{args.version}{suffix}"
        if exported.resolve() != destination.resolve():
            if exported.is_dir():
                shutil.copytree(exported, destination, dirs_exist_ok=True)
            else:
                destination.write_bytes(exported.read_bytes())
        artifacts[export_format] = {"path": str(destination), "sha256": sha256(destination)}
    manifest = {
        "version": args.version,
        "source_model": args.model,
        "classes": PROMPTS,
        "input_size": 640,
        "quantization": "int8",
        "artifacts": artifacts,
    }
    (args.output_dir / f"{args.version}.json").write_text(
        json.dumps(manifest, indent=2) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
