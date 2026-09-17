"""Validate that YOLO train and test images do not share filming sessions."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}
CLASS_COUNT = 3


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
