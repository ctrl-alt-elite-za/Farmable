"""Fit crop diameter-to-weight ranges from measured CSV data."""

from __future__ import annotations

import argparse
import csv
import json
import math
from pathlib import Path


def load_measurements(path: Path) -> list[tuple[float, float]]:
    with path.open(newline="", encoding="utf-8") as handle:
        rows = csv.DictReader(handle)
        if not rows.fieldnames or not {"diameter_cm", "weight_g"} <= set(rows.fieldnames):
            raise ValueError("measurements must contain diameter_cm and weight_g columns")
        values = [(float(r["diameter_cm"]), float(r["weight_g"])) for r in rows]
    if len(values) < 20:
        raise ValueError(f"{path} contains {len(values)} rows; at least 20 are required")
    return values


def fit_range(values: list[tuple[float, float]], holdout: int = 5) -> dict[str, float | int]:
    if len(values) <= holdout:
        raise ValueError("not enough rows for a held-out evaluation")
    train, test = values[:-holdout], values[-holdout:]
    x_mean = sum(x for x, _ in train) / len(train)
    y_mean = sum(y for _, y in train) / len(train)
    denominator = sum((x - x_mean) ** 2 for x, _ in train)
    slope = sum((x - x_mean) * (y - y_mean) for x, y in train) / denominator if denominator else 0.0
    intercept = y_mean - slope * x_mean
    residual = math.sqrt(
        sum((y - (intercept + slope * x)) ** 2 for x, y in train) / max(1, len(train) - 2)
    )
    lower = [intercept + slope * x - 1.282 * residual for x, _ in test]
    upper = [intercept + slope * x + 1.282 * residual for x, _ in test]
    inside = sum(
        lo <= y <= hi
        for (lo, hi), (_, y) in zip(zip(lower, upper, strict=True), test, strict=True)
    )
    return {
        "slope_g_per_cm": slope,
        "intercept_g": intercept,
        "range_residual_g": residual,
        "held_out": len(test),
        "inside": inside,
        "coverage": inside / len(test),
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="+", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    result = {path.stem: fit_range(load_measurements(path)) for path in args.paths}
    print(json.dumps(result, indent=2, sort_keys=True))
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(
            json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
    return 0 if all(float(value["coverage"]) >= 0.8 for value in result.values()) else 1


if __name__ == "__main__":
    raise SystemExit(main())
