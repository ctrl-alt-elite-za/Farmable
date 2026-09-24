"""Explicit bounded reference-data import command; never runs during API startup."""

import argparse
from pathlib import Path

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.reference_imports import MAX_REFERENCE_BUNDLE_BYTES, import_bundle


def read_bundle(path: Path) -> bytes:
    if path.is_symlink() or not path.is_file():
        raise ValueError("reference bundle must be a regular file")
    with path.open("rb") as stream:
        raw = stream.read(MAX_REFERENCE_BUNDLE_BYTES + 1)
    if len(raw) > MAX_REFERENCE_BUNDLE_BYTES:
        raise ValueError("reference bundle has invalid size")
    return raw


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("bundle", type=Path)
    args = parser.parse_args(argv)
    database = Database(Settings())
    try:
        status, rows = import_bundle(database.sessions, read_bundle(args.bundle))
        print(f"reference-import status={status} rows={rows}")
        return 0
    except (OSError, ValueError):
        print("reference-import status=rejected")
        return 1
    finally:
        database.close()


if __name__ == "__main__":
    raise SystemExit(main())
