"""Run Amendment 2 only after its independent mainline registration."""

import argparse
import hashlib
import importlib.metadata
import json
import platform
import sys
from collections import Counter
from dataclasses import asdict
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "ml/backtest"))

from check_protocol_first import check_amendment_two_merged  # noqa: E402
from farmable_ml.cpi import read_cpi  # noqa: E402
from farmable_ml.reports import (  # noqa: E402
    build_report,
    canonical_json,
    render_sentence,
    render_table,
)
from farmable_ml.retrospective import RetrospectiveSimulation  # noqa: E402
from farmable_ml.scenario import MARKET, to_retrospective_2025  # noqa: E402
from farmable_ml.seven_default import (  # noqa: E402
    DECISION_ASSUMPTIONS,
    SCENARIO_ID,
    VERSION_ONE_RUN_ID,
    tomato_price_forecasts,
    validate_tomato_price_rows,
)
from run_retrospective import digest, exact, load_workbooks, write_ledger  # noqa: E402


def identity(repo: Path, amendment_commit: str, inputs: dict[str, str]) -> dict[str, Any]:
    """Capture every code/configuration input that can change the amended run."""
    old_dir = repo / "ml/backtest/results" / VERSION_ONE_RUN_ID
    paths = [
        repo / "ml/backtest/PROTOCOL.md",
        repo / "uv.lock",
        repo / "apps/ml-service/pyproject.toml",
        repo / "ml/backtest/check_protocol_first.py",
        repo / "ml/backtest/run_retrospective.py",
        repo / "ml/backtest/run_seven_default.py",
        repo / "scripts/audit_issue20_market_workbooks.py",
        *(
            old_dir / name
            for name in (
                "decision_backtest.json",
                "decision_backtest.md",
                "slide_sentence.txt",
            )
        ),
        *sorted((repo / "apps/ml-service/src/farmable_ml").glob("*.py")),
    ]
    return {
        "scenario": SCENARIO_ID,
        "amendment_commit": amendment_commit,
        "version_one_run_id": VERSION_ONE_RUN_ID,
        "files": {path.relative_to(repo).as_posix(): digest(path) for path in paths},
        "input_hashes": dict(sorted(inputs.items())),
        "assumptions": exact({crop: asdict(value) for crop, value in DECISION_ASSUMPTIONS.items()}),
        "dependencies": {
            name: importlib.metadata.version(name)
            for name in ("lightgbm", "numpy", "pyarrow", "xlrd", "openpyxl")
        },
        "python": platform.python_version(),
        "platform": platform.system(),
        "bootstrap_replicates": 10000,
        "seed": 20,
    }


def run(repo: Path, workbooks: Path, output: Path, main_ref: str = "origin/main") -> str:
    amendment_commit = check_amendment_two_merged(repo=repo, main_ref=main_ref)
    audit = repo / "ml/data/market_workbook_audit.json"
    cpi_path = repo / "ml/data/cpi_za_monthly.csv"
    inputs = {
        "market_workbook_audit.json": digest(audit),
        "cpi_za_monthly.csv": digest(cpi_path),
        "budget_source_audit.json": digest(repo / "ml/data/budget_source_audit.json"),
        "calendar_source_audit.json": digest(repo / "ml/data/calendar_source_audit.json"),
    }
    for source in json.loads(audit.read_bytes())["sources"]:
        inputs[source["filename"]] = source["sha256"]
    provenance = identity(repo, amendment_commit, inputs)
    run_id = hashlib.sha256(canonical_json(provenance)).hexdigest()
    forecast_dir = output / "forecast/price_only_results" / run_id
    decision_dir = output / "backtest/results" / run_id
    if forecast_dir.exists() or decision_dir.exists():
        raise ValueError("run output already exists; use a separate output root for verification")

    raw = load_workbooks(audit, workbooks)
    cpi = read_cpi(cpi_path.read_bytes())
    simulation = RetrospectiveSimulation(
        raw, cpi, market=MARKET, assumptions=DECISION_ASSUMPTIONS
    ).run()
    prices = to_retrospective_2025(raw, cpi)
    tomato_rows = tomato_price_forecasts(prices, market=MARKET)
    validate_tomato_price_rows(tomato_rows)
    report = build_report(
        simulation.decisions,
        input_hashes=inputs,
        data_kind="historical",
        scenario=SCENARIO_ID,
        observation_cutoff_verified=True,
    )
    old_dir = repo / "ml/backtest/results" / VERSION_ONE_RUN_ID
    old_report = json.loads((old_dir / "decision_backtest.json").read_bytes())
    old_sentence = (old_dir / "slide_sentence.txt").read_text(encoding="utf-8")
    old_table = (old_dir / "decision_backtest.md").read_text(encoding="utf-8")
    if old_report["scenario"] == SCENARIO_ID:
        raise ValueError("version 1 comparison must use the original eight-default scenario")
    comparison = {
        "version_one": {
            "run_id": VERSION_ONE_RUN_ID,
            "report": old_report,
            "sentence": old_sentence,
        },
        "seven_default": {"run_id": run_id, "report": report, "sentence": render_sentence(report)},
        "interpretation": (
            "The decision universes differ. A change in pooled gains cannot be attributed "
            "to improved model skill."
        ),
    }
    comparison_markdown = (
        "# Issue 20 retrospective result comparison\n\n"
        "Version 1 includes eight starting crops and uses a processing-tomato "
        "budget against fresh-market prices. Amendment 2 has seven starting "
        "crops and excludes tomatoes from all decision economics. A difference "
        "in pooled gains cannot be attributed to improved model skill.\n\n"
        "## Version 1: eight defaults\n\n"
        f"{old_sentence.strip()}\n\n{old_table}\n"
        "## Amendment 2: seven defaults\n\n"
        f"{render_sentence(report).strip()}\n\n{render_table(report)}"
    )
    forecast_artifacts = {
        "tomato_price_forecasts.json": canonical_json(
            {
                "scenario": SCENARIO_ID,
                "run_id": run_id,
                "input_hashes": dict(sorted(inputs.items())),
                "rows": exact(tomato_rows),
            }
        ),
        "forecast_selections.json": canonical_json(
            {
                "scenario": SCENARIO_ID,
                "run_id": run_id,
                "selections": exact(
                    [
                        asdict(forecast)
                        for choice in simulation.choices
                        for forecast in choice.forecasts
                    ]
                ),
            }
        ),
    }
    decision_artifacts = {
        "decision_backtest.json": canonical_json(report),
        "decision_backtest.md": render_table(report).encode("utf-8"),
        "slide_sentence.txt": render_sentence(report).encode("utf-8"),
        "version_comparison.json": canonical_json(comparison),
        "version_comparison.md": comparison_markdown.encode("utf-8"),
    }
    forecast_dir.mkdir(parents=True)
    decision_dir.mkdir(parents=True)
    for directory, artifacts in (
        (forecast_dir, forecast_artifacts),
        (decision_dir, decision_artifacts),
    ):
        for name, payload in artifacts.items():
            (directory / name).write_bytes(payload)
    write_ledger(
        [asdict(row) for row in simulation.decisions], decision_dir / "decision_ledger.parquet"
    )
    manifest = {
        "run_id": run_id,
        "data_kind": "retrospective",
        "identity": provenance,
        "input_hashes": inputs,
        "row_counts": {
            "decisions": len(simulation.decisions),
            "tomato_price_forecasts": len(tomato_rows),
        },
        "skip_reasons": dict(
            sorted(
                Counter(row.skip_reason for row in simulation.decisions if row.skip_reason).items()
            )
        ),
        "artifacts": {
            path.relative_to(output).as_posix(): digest(path)
            for directory in (forecast_dir, decision_dir)
            for path in sorted(directory.iterdir())
        },
    }
    for directory in (forecast_dir, decision_dir):
        (directory / "manifest.json").write_bytes(canonical_json(manifest))
    return run_id


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--workbooks", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=ROOT / "ml")
    parser.add_argument("--main-ref", default="origin/main")
    args = parser.parse_args()
    print(run(ROOT, args.workbooks, args.output, args.main_ref))


if __name__ == "__main__":
    main()
