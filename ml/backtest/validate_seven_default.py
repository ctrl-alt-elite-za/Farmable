"""Verify Amendment 2 result bytes against the decision ledger and manifest."""

import argparse
import hashlib
import json
import re
import sys
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ml/forecast"))

from farmable_ml.data import Crop  # noqa: E402
from farmable_ml.decision import Decision  # noqa: E402
from farmable_ml.reports import (  # noqa: E402
    Bootstrap,
    build_report,
    canonical_json,
    render_sentence,
    render_table,
)
from farmable_ml.seven_default import SCENARIO_ID, VERSION_ONE_RUN_ID  # noqa: E402
from validate_tomato_price import validate as validate_tomato_price  # noqa: E402


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _decision(row: dict[str, Any]) -> Decision:
    return Decision(
        date.fromisoformat(row["origin"]),
        Crop(row["default"]),
        Crop(row["recommended"]),
        Decimal(row["default_margin"]) if row["default_margin"] is not None else None,
        Decimal(row["recommended_margin"]) if row["recommended_margin"] is not None else None,
        row["skip_reason"],
    )


def validate(output: Path, run_id: str) -> None:
    if re.fullmatch(r"[0-9a-f]{64}", run_id) is None:
        raise ValueError("invalid run ID")
    forecast_dir = output / "forecast/price_only_results" / run_id
    decision_dir = output / "backtest/results" / run_id
    first_manifest = (forecast_dir / "manifest.json").read_bytes()
    if first_manifest != (decision_dir / "manifest.json").read_bytes():
        raise ValueError("result manifests differ")
    manifest = json.loads(first_manifest)
    if (
        manifest["run_id"] != run_id
        or manifest["identity"]["scenario"] != SCENARIO_ID
        or hashlib.sha256(canonical_json(manifest["identity"])).hexdigest() != run_id
        or manifest["row_counts"] != {"decisions": 1092, "tomato_price_forecasts": 12}
    ):
        raise ValueError("result manifest identity or row counts are invalid")
    expected = {
        path.relative_to(output).as_posix(): _digest(path)
        for directory in (forecast_dir, decision_dir)
        for path in directory.iterdir()
        if path.is_file() and path.name != "manifest.json"
    }
    required = {
        f"forecast/price_only_results/{run_id}/{name}"
        for name in ("tomato_price_forecasts.json", "forecast_selections.json")
    } | {
        f"backtest/results/{run_id}/{name}"
        for name in (
            "decision_ledger.parquet",
            "decision_backtest.json",
            "decision_backtest.md",
            "slide_sentence.txt",
            "version_comparison.json",
            "version_comparison.md",
        )
    }
    if set(expected) != required or manifest["artifacts"] != expected:
        raise ValueError("result artifact hashes do not match manifest")

    ledger = pq.read_table(decision_dir / "decision_ledger.parquet").to_pylist()
    if len(ledger) != 1092:
        raise ValueError("decision ledger must contain 1,092 rows")
    rows = tuple(_decision(row) for row in ledger)
    actual_report = (decision_dir / "decision_backtest.json").read_bytes()
    recorded = json.loads(actual_report)
    if recorded["scenario"] != SCENARIO_ID or recorded["data_kind"] != "historical":
        raise ValueError("incorrect decision report scenario")
    if recorded["input_hashes"] != manifest["input_hashes"]:
        raise ValueError("report input hashes do not match manifest")
    bootstrap = recorded["bootstrap"]
    calculated = build_report(
        rows,
        input_hashes=recorded["input_hashes"],
        data_kind="historical",
        scenario=SCENARIO_ID,
        observation_cutoff_verified=True,
        config=Bootstrap(
            replicates=int(bootstrap["replicates"]),
            seed=int(bootstrap["seed"]),
            minimum_valid_fraction=Decimal(str(bootstrap["minimum_valid_fraction"])),
        ),
    )
    if actual_report != canonical_json(calculated):
        raise ValueError("decision report does not match scored ledger")
    if (decision_dir / "decision_backtest.md").read_bytes() != render_table(calculated).encode(
        "utf-8"
    ):
        raise ValueError("decision table does not match report")
    if (decision_dir / "slide_sentence.txt").read_bytes() != render_sentence(calculated).encode(
        "utf-8"
    ):
        raise ValueError("slide sentence does not match report")
    validate_tomato_price(forecast_dir / "tomato_price_forecasts.json")
    tomato = json.loads((forecast_dir / "tomato_price_forecasts.json").read_bytes())
    if tomato["run_id"] != run_id or tomato["input_hashes"] != manifest["input_hashes"]:
        raise ValueError("tomato prices do not match run identity")
    comparison = json.loads((decision_dir / "version_comparison.json").read_bytes())
    old_dir = ROOT / "ml/backtest/results" / VERSION_ONE_RUN_ID
    if (
        comparison["version_one"]["run_id"] != VERSION_ONE_RUN_ID
        or comparison["version_one"]["report"]
        != json.loads((old_dir / "decision_backtest.json").read_bytes())
        or comparison["version_one"]["sentence"]
        != (old_dir / "slide_sentence.txt").read_text(encoding="utf-8")
        or comparison["seven_default"]
        != {
            "run_id": run_id,
            "report": json.loads(actual_report),
            "sentence": render_sentence(calculated),
        }
    ):
        raise ValueError("version comparison does not match both published results")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("run_id")
    parser.add_argument("--output", type=Path, default=ROOT / "ml")
    args = parser.parse_args()
    validate(args.output, args.run_id)
    print("Validated seven-default decision and tomato price-only artifacts.")


if __name__ == "__main__":
    main()
