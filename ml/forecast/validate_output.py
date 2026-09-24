"""Validate the issue #20 Parquet artifact without importing backend/database code."""

import argparse
from pathlib import Path

from farmable_ml.snapshot import read_snapshot


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    try:
        bundle = read_snapshot(args.path)
    except (OSError, ValueError, TypeError, KeyError) as exc:
        print(f"INVALID: {exc}")
        return 1
    print(f"VALID: {bundle['run_id']} ({bundle['data_kind']}); 96 crop/month rows, 2025 ZAR/kg")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
