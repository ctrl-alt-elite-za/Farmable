"""Create a hashed fixed-fixture manifest from supplied real images.

This command records fixture identity only. It deliberately does not run model
inference or mark a crop as detected; platform results belong in the later
physical-device report.
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
from typing import Any

REQUIRED_CROPS = ("cabbage", "tomato", "spinach", "negative")
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp", ".heic"}


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def build_manifest(root: Path, model_version: str) -> dict[str, object]:
    if not root.is_dir():
        raise ValueError(f"fixture root does not exist: {root}")
    fixtures: list[dict[str, str | None]] = []
    fixture_ids: set[str] = set()
    for crop in REQUIRED_CROPS:
        directory = root / crop
        images = (
            sorted(
                path
                for path in directory.iterdir()
                if path.is_file() and path.suffix.lower() in IMAGE_SUFFIXES
            )
            if directory.is_dir()
            else []
        )
        if len(images) < 2:
            raise ValueError(f"{directory} needs at least two real image fixtures")
        for image in images:
            fixture_id = f"{crop}-{image.stem}"
            if fixture_id in fixture_ids:
                raise ValueError(f"duplicate fixture id: {fixture_id}")
            fixture_ids.add(fixture_id)
            fixtures.append(
                {
                    "fixture_id": fixture_id,
                    "fixture_sha256": sha256(image),
                    "expected_crop": None if crop == "negative" else crop,
                    "path": image.relative_to(root).as_posix(),
                }
            )
    return {"schema_version": 1, "model_version": model_version, "fixtures": fixtures}


def build_release_report(
    manifest: dict[str, object],
    ios_artifact_sha256: str,
    android_artifact_sha256: str,
    ios_results: list[dict[str, Any]],
    android_results: list[dict[str, Any]],
) -> dict[str, object]:
    """Assemble the canonical fixture report consumed by ``release.py``."""
    fixtures = manifest.get("fixtures")
    if not isinstance(fixtures, list):
        raise ValueError("fixture manifest must contain fixtures")
    fixture_set = [
        {
            "fixture_id": fixture["fixture_id"],
            "fixture_sha256": fixture["fixture_sha256"],
            "expected_crop": fixture["expected_crop"],
        }
        for fixture in fixtures
        if isinstance(fixture, dict)
    ]
    model_version = manifest.get("model_version")
    if not isinstance(model_version, str) or not model_version:
        raise ValueError("fixture manifest model_version must be non-empty")
    return {
        "schema_version": 1,
        "model_version": model_version,
        "fixture_set": fixture_set,
        "runs": {
            "ios": {"artifact_sha256": ios_artifact_sha256, "results": ios_results},
            "android": {
                "artifact_sha256": android_artifact_sha256,
                "results": android_results,
            },
        },
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--model-version", default="demo1")
    parser.add_argument("--ios-results", type=Path)
    parser.add_argument("--android-results", type=Path)
    parser.add_argument("--ios-artifact-sha256")
    parser.add_argument("--android-artifact-sha256")
    args = parser.parse_args()
    try:
        manifest = build_manifest(args.root, args.model_version)
    except ValueError as error:
        parser.error(str(error))
    assembly_args = (
        args.ios_results,
        args.android_results,
        args.ios_artifact_sha256,
        args.android_artifact_sha256,
    )
    if any(value is not None for value in assembly_args) and not all(
        value is not None for value in assembly_args
    ):
        parser.error("assembly requires both result files and both artifact SHA-256 values")
    if all(value is not None for value in assembly_args):
        try:
            ios_results = json.loads(args.ios_results.read_text(encoding="utf-8"))
            android_results = json.loads(args.android_results.read_text(encoding="utf-8"))
            if not isinstance(ios_results, list) or not isinstance(android_results, list):
                raise ValueError("result files must contain JSON arrays")
            manifest = build_release_report(
                manifest,
                args.ios_artifact_sha256,
                args.android_artifact_sha256,
                ios_results,
                android_results,
            )
        except (OSError, json.JSONDecodeError, ValueError) as error:
            parser.error(str(error))
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
