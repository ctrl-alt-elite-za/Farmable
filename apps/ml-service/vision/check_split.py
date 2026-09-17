"""Validate that YOLO train and test images do not share filming sessions."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}
CLASS_COUNT = 3
CROPS = {"cabbage", "tomato", "spinach"}


def read_sessions(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = csv.DictReader(handle)
        if not rows.fieldnames or not {"image", "session_id"} <= set(rows.fieldnames):
            raise ValueError("manifest must contain image and session_id columns")
        result: dict[str, str] = {}
        for row in rows:
            image, session = row["image"].strip().replace("\\", "/"), row["session_id"].strip()
            if not image or not session:
                raise ValueError("manifest rows require non-empty image and session_id")
            if image in result and result[image] != session:
                raise ValueError(f"image {image!r} has multiple sessions")
            result[image] = session
        return result


def read_crop_manifest(path: Path) -> dict[str, tuple[str, str]]:
    """Read image sessions plus the crop represented by each image."""
    with path.open(newline="", encoding="utf-8") as handle:
        rows = csv.DictReader(handle)
        required = {"image", "session_id", "crop"}
        if not rows.fieldnames or not required <= set(rows.fieldnames):
            raise ValueError("manifest must contain image, session_id, and crop columns")
        result: dict[str, tuple[str, str]] = {}
        for row in rows:
            image = row["image"].strip().replace("\\", "/")
            session = row["session_id"].strip()
            crop = row["crop"].strip().lower()
            if not image or not session or not crop:
                raise ValueError("manifest rows require non-empty image, session_id, and crop")
            if crop not in CROPS:
                raise ValueError(f"unsupported crop {crop!r}; expected cabbage, tomato, or spinach")
            record = (session, crop)
            if image in result and result[image] != record:
                raise ValueError(f"image {image!r} has conflicting manifest entries")
            result[image] = record
        return result


def count_crop_images(train: Path, test: Path, manifest: Path) -> dict[str, int]:
    """Count real images per crop, requiring every image to be in the manifest."""
    records = read_crop_manifest(manifest)
    by_stem: dict[str, list[str]] = {}
    for key in records:
        by_stem.setdefault(Path(key).stem, []).append(key)
    counts = {crop: 0 for crop in CROPS}
    for image, root in [
        (p, train) for p in train.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
    ] + [(p, test) for p in test.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES]:
        relative = image.relative_to(root).as_posix()
        matches = [key for key in (relative, image.name) if key in records]
        if not matches and len(by_stem.get(image.stem, [])) == 1:
            matches = by_stem[image.stem]
        matches = list(dict.fromkeys(matches))
        if len(matches) != 1:
            raise ValueError(f"image {image.name!r} must map to exactly one crop manifest entry")
        counts[records[matches[0]][1]] += 1
    return counts


def split_sessions(train: Path, test: Path, manifest: Path) -> tuple[set[str], set[str]]:
    sessions = read_sessions(manifest)
    train_images = [
        p for p in train.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
    ]
    test_images = [p for p in test.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES]
    by_stem: dict[str, list[str]] = {}
    for key in sessions:
        by_stem.setdefault(Path(key).stem, []).append(key)
    image_sessions: dict[Path, str] = {}
    missing: list[str] = []
    for image, root in [(p, train) for p in train_images] + [(p, test) for p in test_images]:
        relative = image.relative_to(root).as_posix()
        candidates = [relative, image.name]
        matches = list(
            dict.fromkeys(candidate for candidate in candidates if candidate in sessions)
        )
        if not matches and len(by_stem.get(image.stem, [])) == 1:
            matches = by_stem[image.stem]
        if not matches:
            missing.append(image.name)
        elif len(matches) > 1:
            raise ValueError(f"image {image.name!r} matches multiple manifest entries")
        else:
            image_sessions[image] = sessions[matches[0]]
    if missing:
        raise ValueError(f"manifest has no session for {missing[0]!r}")
    return ({image_sessions[p] for p in train_images}, {image_sessions[p] for p in test_images})


def validate_labels(image_root: Path) -> dict[int, int]:
    """Validate YOLO labels beside ``image_root`` and count labelled images."""
    label_root = image_root.parent / "labels"
    counts = {class_id: 0 for class_id in range(CLASS_COUNT)}
    for image in image_root.rglob("*"):
        if not image.is_file() or image.suffix.lower() not in IMAGE_SUFFIXES:
            continue
        label = label_root / image.relative_to(image_root).with_suffix(".txt")
        if not label.is_file():
            raise ValueError(f"missing label for {image.name!r}")
        seen: set[int] = set()
        for line_number, line in enumerate(label.read_text(encoding="utf-8").splitlines(), 1):
            fields = line.split()
            if len(fields) != 5:
                raise ValueError(f"{label}:{line_number}: expected 5 YOLO fields")
            class_id = int(fields[0])
            coordinates = [float(value) for value in fields[1:]]
            if (
                class_id not in counts
                or any(not 0 <= value <= 1 for value in coordinates)
                or coordinates[2] <= 0
                or coordinates[3] <= 0
            ):
                raise ValueError(f"{label}:{line_number}: invalid YOLO annotation")
            seen.add(class_id)
        for class_id in seen:
            counts[class_id] += 1
    return counts


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", type=Path, required=True)
    parser.add_argument("--test", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    parser.add_argument("--min-images-per-class", type=int, default=300)
    args = parser.parse_args()
    try:
        train_ids, test_ids = split_sessions(args.train, args.test, args.manifest)
        train_counts = validate_labels(args.train)
        test_counts = validate_labels(args.test)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    overlap = train_ids & test_ids
    if overlap:
        print("overlapping sessions: " + ", ".join(sorted(overlap)))
        return 1
    if not train_ids or not test_ids:
        print("both train and test must contain at least one session")
        return 1
    for class_id in range(CLASS_COUNT):
        total = train_counts[class_id] + test_counts[class_id]
        if total < args.min_images_per_class:
            print(
                f"class {class_id} has {total} labelled images; "
                f"minimum is {args.min_images_per_class}"
            )
            return 1
    print(f"PASS: {len(train_ids)} train sessions and {len(test_ids)} disjoint test sessions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
