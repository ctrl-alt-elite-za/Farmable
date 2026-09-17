"""Validate that YOLO train and test images do not share filming sessions."""

from __future__ import annotations

import argparse
import csv
from pathlib import Path

IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png"}


def read_sessions(path: Path) -> dict[str, str]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = csv.DictReader(handle)
        if not rows.fieldnames or not {"image", "session_id"} <= set(rows.fieldnames):
            raise ValueError("manifest must contain image and session_id columns")
        result: dict[str, str] = {}
        for row in rows:
            image, session = Path(row["image"].strip()).stem, row["session_id"].strip()
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
    test_images = [
        p for p in test.rglob("*") if p.is_file() and p.suffix.lower() in IMAGE_SUFFIXES
    ]
    missing = [p.stem for p in train_images + test_images if p.stem not in sessions]
    if missing:
        raise ValueError(f"manifest has no session for {missing[0]!r}")
    return ({sessions[p.stem] for p in train_images}, {sessions[p.stem] for p in test_images})


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--train", type=Path, required=True)
    parser.add_argument("--test", type=Path, required=True)
    parser.add_argument("--manifest", type=Path, required=True)
    args = parser.parse_args()
    try:
        train_ids, test_ids = split_sessions(args.train, args.test, args.manifest)
    except (OSError, ValueError) as error:
        parser.error(str(error))
    overlap = train_ids & test_ids
    if overlap:
        print("overlapping sessions: " + ", ".join(sorted(overlap)))
        return 1
    if not train_ids or not test_ids:
        print("both train and test must contain at least one session")
        return 1
    print(f"PASS: {len(train_ids)} train sessions and {len(test_ids)} disjoint test sessions")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
