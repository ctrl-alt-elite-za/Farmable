"""Validate Amendment 2's separate 12-month tomato price-only JSON artifact."""

import argparse
import json
from datetime import date
from decimal import Decimal
from pathlib import Path

from farmable_ml.seven_default import SCENARIO_ID, validate_tomato_price_rows


def validate(path: Path) -> None:
    document = json.loads(path.read_bytes())
    if set(document) != {"scenario", "run_id", "input_hashes", "rows"}:
        raise ValueError("incorrect tomato price artifact envelope")
    if document["scenario"] != SCENARIO_ID:
        raise ValueError("incorrect tomato price scenario")
    run_id = document["run_id"]
    if (
        not isinstance(run_id, str)
        or len(run_id) != 64
        or any(character not in "0123456789abcdef" for character in run_id)
    ):
        raise ValueError("invalid run ID")
    hashes = document["input_hashes"]
    if (
        not isinstance(hashes, dict)
        or not hashes
        or any(
            not isinstance(value, str)
            or len(value) != 64
            or any(character not in "0123456789abcdef" for character in value)
            for value in hashes.values()
        )
    ):
        raise ValueError("invalid input source hashes")
    rows = document["rows"]
    if not isinstance(rows, list):
        raise ValueError("tomato rows must be a list")
    parsed = []
    for row in rows:
        if not isinstance(row, dict):
            raise ValueError("tomato price row must be an object")
        converted = dict(row)
        for field in ("target_month", "as_of"):
            converted[field] = date.fromisoformat(converted[field])
        for field in ("p10", "p50", "p90"):
            converted[field] = Decimal(converted[field])
        parsed.append(converted)
    validate_tomato_price_rows(parsed)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("path", type=Path)
    args = parser.parse_args()
    validate(args.path)
    print("Validated 12 tomato price-only forecast rows.")


if __name__ == "__main__":
    main()
