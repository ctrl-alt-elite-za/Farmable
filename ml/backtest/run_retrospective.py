"""Credential-free Issue 20 runner; verify protocol history before reading real inputs.

Run from the repository root with xlrd==2.0.2 and openpyxl==3.1.5 installed.
Raw workbooks are local files named by the committed audit; no database is used.
"""

import argparse
import hashlib
import importlib.metadata
import json
import platform
import sys
from collections import Counter
from dataclasses import asdict
from datetime import date
from decimal import Decimal
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.parquet as pq

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(ROOT / "ml/backtest"))

from audit_issue20_market_workbooks import audit_rows, read_sheet  # noqa: E402
from check_protocol_first import check_protocol_first  # noqa: E402
from farmable_ml.cpi import read_cpi  # noqa: E402
from farmable_ml.data import Crop, ObservationPolicy, PriceObservation  # noqa: E402
from farmable_ml.experiment import Experiment  # noqa: E402
from farmable_ml.forecast import historical_range, shift_month  # noqa: E402
from farmable_ml.reports import (  # noqa: E402
    RETROSPECTIVE_CAVEATS,
    RETROSPECTIVE_SCENARIO,
    build_report,
    canonical_json,
    render_sentence,
    render_table,
)
from farmable_ml.retrospective import RetrospectiveSimulation  # noqa: E402
from farmable_ml.scenario import (  # noqa: E402
    ASSUMPTIONS,
    MARKET,
    SCENARIO_ID,
    to_retrospective_2025,
)
from farmable_ml.snapshot import consumer_json, write_snapshot  # noqa: E402


def digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def exact(value: Any) -> Any:
    """Keep full decimal arithmetic and dates in ledgers, with canonical ordering."""
    if isinstance(value, Decimal):
        return str(value)
    if isinstance(value, date):
        return value.isoformat()
    if isinstance(value, dict):
        return {str(key): exact(item) for key, item in value.items()}
    if isinstance(value, list | tuple):
        return [exact(item) for item in value]
    if isinstance(value, set | frozenset):
        return [exact(item) for item in sorted(value)]
    return value


def load_workbooks(audit_path: Path, directory: Path) -> tuple[PriceObservation, ...]:
    audit = json.loads(audit_path.read_bytes())
    sources = audit["sources"]
    if sorted(int(source["year"]) for source in sources) != list(range(2008, 2025)):
        raise ValueError("requires exactly the registered 2008-2024 workbook series")
    records = []
    for source in sorted(sources, key=lambda item: item["year"]):
        filename = source["filename"]
        if Path(filename).name != filename:
            raise ValueError("workbook filename must be a basename")
        path = directory / filename
        if path.stat().st_size != source["bytes"] or digest(path) != source["sha256"]:
            raise ValueError(f"workbook bytes/hash mismatch: {filename}")
        sheet, rows = read_sheet(path)
        year = int(source["year"])
        checked = audit_rows(rows, year)
        if sheet != source["sheet"] or checked != source["crops"]:
            raise ValueError(f"workbook does not match the reviewed cell audit: {filename}")
        header = next(row for row in rows[:10] if "PRODUCT" in row)
        first = header.index("J")
        for crop in Crop:
            detail = checked[crop.value]
            if detail["valid_months"] != list(range(1, 13)):
                raise ValueError(f"incomplete registered workbook: {filename}/{crop}")
            for month in range(1, 13):
                observation = date(year, month, 1)
                records.append(
                    PriceObservation(
                        crop,
                        MARKET,
                        observation,
                        shift_month(observation, 1),
                        Decimal(str(rows[detail["price_row"] - 1][first + month - 1])) / 1000,
                        source["sha256"],
                        availability_kind="analytical_next_month",
                    )
                )
    return tuple(records)


def identity(repo: Path, protocol_commit: str) -> dict[str, Any]:
    paths = [
        repo / "ml/backtest/PROTOCOL.md",
        repo / "uv.lock",
        repo / "apps/ml-service/pyproject.toml",
        repo / "ml/data/market_workbook_audit.json",
        repo / "ml/data/cpi_za_monthly.csv",
        repo / "ml/data/budget_source_audit.json",
        repo / "ml/data/calendar_source_audit.json",
        repo / "scripts/audit_issue20_market_workbooks.py",
        repo / "ml/backtest/check_protocol_first.py",
        repo / "ml/backtest/run_retrospective.py",
        *sorted((repo / "apps/ml-service/src/farmable_ml").glob("*.py")),
    ]
    return {
        "scenario": SCENARIO_ID,
        "protocol_commit": protocol_commit,
        "files": {path.relative_to(repo).as_posix(): digest(path) for path in paths},
        "dependencies": {
            name: importlib.metadata.version(name)
            for name in ("lightgbm", "numpy", "pyarrow", "xlrd", "openpyxl")
        },
        "python": platform.python_version(),
        "platform": platform.system(),
        "configuration": {
            "assumptions": exact({crop: asdict(value) for crop, value in ASSUMPTIONS.items()}),
            "bootstrap_replicates": 10000,
            "seed": 20,
            "snapshot_year": 2025,
        },
    }


def snapshot(experiment: Experiment, run_id: str, sources: dict[str, str]) -> dict[str, Any]:
    rows = []
    cutoff = date(2025, 1, 1)
    for crop in Crop:
        assumption = ASSUMPTIONS[crop]
        for month in range(1, 13):
            target = shift_month(date(2025, month, 1), assumption.harvest_offset_months)
            forecast = historical_range(
                experiment.records,
                crop=crop,
                market=MARKET,
                origin=cutoff,
                target=target,
                policy=ObservationPolicy.RETROSPECTIVE,
            )
            rows.append(
                {
                    "crop": crop.value,
                    "plant_month": month,
                    "growing_months": assumption.harvest_offset_months,
                    "p10": forecast.p10.quantize(Decimal("0.0001")),
                    "p50": forecast.p50.quantize(Decimal("0.0001")),
                    "p90": forecast.p90.quantize(Decimal("0.0001")),
                    "method": forecast.method,
                    "cost_per_ha": assumption.cost_rand_per_ha.quantize(Decimal("0.0001")),
                    "yield_kg_per_ha": assumption.yield_kg_per_ha.quantize(Decimal("0.0001")),
                }
            )
    return {
        "schema_version": 1,
        "run_id": run_id,
        "data_kind": "retrospective",
        "as_of": "2026-09-23T00:00:00+00:00",
        "currency": "ZAR",
        "price_basis_year": 2025,
        "sources": [{"name": name, "sha256": sha} for name, sha in sorted(sources.items())],
        "assumptions": RETROSPECTIVE_CAVEATS
        + [
            "Snapshot planting months refer to 2025; history ends in December 2024.",
            "Deployment snapshot uses frozen pre-2025 historical ranges under Amendment 1.",
            "As-of denotes the registered scenario date, not source publication availability.",
            "Prices are gross market prices; decision margins also deduct crop marketing rates.",
            "All planting months are exported; calendar eligibility remains a separate constraint.",
        ],
        "rows": rows,
    }


def write_ledger(rows: list[dict[str, Any]], path: Path) -> None:
    # Decimal strings retain every computed digit instead of rounding margins.
    fields = sorted({field for row in rows for field in row})
    table = pa.Table.from_pylist(
        exact([{field: row.get(field) for field in fields} for row in rows])
    )
    pq.write_table(table, path, compression="NONE", use_dictionary=False, version="2.6")


def run(repo: Path, workbooks: Path, output: Path, main_ref: str = "origin/main") -> str:
    gate = check_protocol_first(repo=repo, main_ref=main_ref, check_ready=True)
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
    provenance = identity(repo, gate.protocol_commit)
    run_id = hashlib.sha256(canonical_json(provenance)).hexdigest()
    forecast_dir = output / "forecast/results" / run_id
    decision_dir = output / "backtest/results" / run_id
    if forecast_dir.exists() or decision_dir.exists():
        raise ValueError("run output already exists; use a separate output root for verification")
    raw_records = load_workbooks(audit, workbooks)
    cpi = read_cpi(cpi_path.read_bytes())
    simulation = RetrospectiveSimulation(raw_records, cpi, market=MARKET).run()
    records = to_retrospective_2025(raw_records, cpi)
    experiment = Experiment(records)
    decisions = simulation.decisions
    report = build_report(
        decisions,
        input_hashes=inputs,
        data_kind="historical",
        scenario=RETROSPECTIVE_SCENARIO,
        observation_cutoff_verified=True,
    )
    evaluation = experiment.forecast_evaluation()
    bundle = snapshot(experiment, run_id, inputs)
    selections = [
        asdict(forecast) for choice in simulation.choices for forecast in choice.forecasts
    ]
    forecast_dir.mkdir(parents=True)
    decision_dir.mkdir(parents=True)
    write_snapshot(bundle, forecast_dir / "forecasts.parquet")
    (forecast_dir / "forecast.json").write_bytes(consumer_json(bundle))
    write_ledger(experiment.forecast_ledger(), forecast_dir / "forecast_ledger.parquet")
    write_ledger([asdict(row) for row in decisions], decision_dir / "decision_ledger.parquet")
    (forecast_dir / "forecast_backtest.json").write_bytes(
        canonical_json(
            exact(
                {
                    "data_kind": "retrospective",
                    "unit": "2025 ZAR/kg",
                    "scenario": SCENARIO_ID,
                    "input_hashes": inputs,
                    "selections": selections,
                    **evaluation,
                }
            )
        )
    )
    (decision_dir / "decision_backtest.json").write_bytes(canonical_json(report))
    (decision_dir / "decision_backtest.md").write_text(
        render_table(report), encoding="utf-8", newline="\n"
    )
    (decision_dir / "slide_sentence.txt").write_text(
        render_sentence(report), encoding="utf-8", newline="\n"
    )
    manifest = {
        "run_id": run_id,
        "data_kind": "retrospective",
        "identity": provenance,
        "input_hashes": inputs,
        "caveats": RETROSPECTIVE_CAVEATS,
        "row_counts": {"prices": len(records), "decisions": len(decisions), "snapshot": 96},
        "skip_reasons": dict(
            sorted(Counter(row.skip_reason for row in decisions if row.skip_reason).items())
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
