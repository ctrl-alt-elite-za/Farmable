"""Deterministic every-default reports from a scored decision ledger.

Statistical defaults are proposed settings for protocol review. This module does
not run an experiment or certify that input rows came from public market data.
"""

import hashlib
import json
import random
from collections import defaultdict
from dataclasses import asdict, dataclass
from datetime import date
from decimal import ROUND_HALF_EVEN, Decimal
from pathlib import Path
from typing import Any

from farmable_ml.data import EXCLUDED, Crop
from farmable_ml.decision import Decision
from farmable_ml.forecast import quantile

D = Decimal
HISTORICAL_MONTHS = tuple(
    date(year, month, 1) for year in range(2012, 2025) for month in range(1, 13)
)
HISTORICAL_KEYS = frozenset((month, crop) for month in HISTORICAL_MONTHS for crop in Crop)
CAVEATS = [
    "Simulated decisions are not observed farmer incomes.",
    "Guideline yields and Western Cape budgets are assumptions.",
    "Tomatoes use a processing-tomato budget, not a fresh-market budget.",
    "Year-cluster resampling retains dependence within years, but not between years.",
    "At most 13 planting-year clusters limit confidence-interval interpretation.",
]


@dataclass(frozen=True)
class Bootstrap:
    replicates: int = 10000
    seed: int = 20
    minimum_valid_fraction: Decimal = D("0.9")

    def __post_init__(self) -> None:
        if self.replicates < 100 or not 0 < self.minimum_valid_fraction <= 1:
            raise ValueError("invalid bootstrap settings")


def _interval(rows: tuple[Decision, ...], config: Bootstrap) -> tuple[Any, int, str | None]:
    clusters: dict[int, list[Decimal]] = defaultdict(list)
    for row in rows:
        gains = clusters[row.origin.year]
        if row.default != row.recommended and row.gain is not None:
            gains.append(row.gain)
    years = sorted(clusters)
    if len(years) < 2:
        return None, 0, "fewer_than_two_year_clusters"
    rng = random.Random(config.seed)  # noqa: S311 - reproducible statistical resampling
    medians = []
    for _ in range(config.replicates):
        sample = [gain for year in rng.choices(years, k=len(years)) for gain in clusters[year]]
        if sample:
            medians.append(quantile(sample, D("0.5")))
    if D(len(medians)) / config.replicates < config.minimum_valid_fraction:
        return None, len(medians), "too_few_nonempty_bootstrap_replicates"
    return [quantile(medians, D("0.05")), quantile(medians, D("0.95"))], len(medians), None


def metrics(rows: tuple[Decision, ...], config: Bootstrap) -> dict[str, Any]:
    scorable = tuple(row for row in rows if row.skip_reason is None)
    switches = tuple(row for row in scorable if row.default != row.recommended)
    gains = [row.gain for row in switches if row.gain is not None]
    percentages = [
        100 * row.gain / row.default_margin
        for row in switches
        if row.default_margin is not None and row.default_margin > 0 and row.gain is not None
    ]
    count = len(scorable)
    null_reasons = {}
    result: dict[str, Any] = {
        "decisions": count,
        "eligible": len(rows),
        "skipped": len(rows) - count,
        "switches": len(switches),
        "no_switches": count - len(switches),
        "positive_default_margin_switches": len(percentages),
        "percentage_excluded_switches": len(switches) - len(percentages),
        "switch_rate": D(len(switches)) / count if count else None,
        "switch_win_rate": D(sum(gain > 0 for gain in gains)) / len(gains) if gains else None,
        "median_gain_rand": quantile(gains, D("0.5")) if gains else None,
        "median_gain_pct": quantile(percentages, D("0.5")) if percentages else None,
        "p10_gain_rand": quantile(gains, D("0.1")) if gains else None,
        "worst_loss_rand": min(D(0), min(gains)) if gains else None,
    }
    if gains:
        interval, valid, reason = _interval(scorable, config)
    else:
        interval, valid, reason = None, 0, "no_scorable_switches"
    result.update(
        median_gain_ci90=interval,
        bootstrap_valid_replicates=valid,
        planting_year_clusters=len({row.origin.year for row in scorable}),
    )
    for name, value in result.items():
        if value is None:
            null_reasons[name] = (
                reason
                if name == "median_gain_ci90"
                else "no_scorable_decisions"
                if name == "switch_rate"
                else "no_positive_default_margin_switches"
                if name == "median_gain_pct"
                else "no_scorable_switches"
            )
    result["null_reasons"] = null_reasons
    return result


def build_report(
    rows: tuple[Decision, ...],
    *,
    input_hashes: dict[str, str],
    data_kind: str,
    information_cutoff_verified: bool = False,
    config: Bootstrap | None = None,
) -> dict[str, Any]:
    config = config if config is not None else Bootstrap()
    if data_kind not in {"synthetic", "historical"}:
        raise ValueError("data_kind must be explicit")
    if data_kind == "historical" and not information_cutoff_verified:
        raise ValueError("historical information cutoff is not verified")
    if data_kind == "synthetic" and information_cutoff_verified:
        raise ValueError("synthetic fixtures cannot claim verified historical information")
    if not input_hashes or any(
        len(value) != 64 or any(c not in "0123456789abcdef" for c in value)
        for value in input_hashes.values()
    ):
        raise ValueError("input_hashes must contain lowercase SHA-256 digests")
    ordered = tuple(sorted(rows, key=lambda row: (row.origin, row.default)))
    if len({(row.origin, row.default) for row in ordered}) != len(ordered):
        raise ValueError("duplicate default/planting-month decisions")
    keys = {(row.origin, row.default) for row in ordered}
    if data_kind == "historical":
        unexpected = keys - HISTORICAL_KEYS
        missing = HISTORICAL_KEYS - keys
        if unexpected or missing:
            raise ValueError(
                "insufficient historical coverage: expected every default/planting-month "
                f"key from 2012-01 through 2024-12; {len(missing)} missing, "
                f"{len(unexpected)} out-of-period keys"
            )
    months = sorted({row.origin for row in ordered})
    coverage = {
        "data_kind": data_kind,
        "start_month": months[0].strftime("%Y-%m") if months else None,
        "end_month": months[-1].strftime("%Y-%m") if months else None,
        "observed_months": len(months),
        "decision_keys": len(keys),
        "complete_historical_grid": keys == HISTORICAL_KEYS,
    }
    report = {
        crop.value: metrics(tuple(row for row in ordered if row.default == crop), config)
        for crop in Crop
    }
    report["pooled"] = metrics(ordered, config)
    return {
        "schema_version": 2,
        "data_kind": data_kind,
        "information_policy": {
            "status": (
                "verified_strictly_before_planting"
                if information_cutoff_verified
                else "synthetic_not_applicable"
            )
        },
        "coverage": coverage,
        "currency": "ZAR",
        "price_basis_year": 2025,
        "unit": "ZAR/ha/month",
        "input_hashes": dict(sorted(input_hashes.items())),
        "excluded": dict(EXCLUDED),
        "caveats": CAVEATS,
        "bootstrap": asdict(config),
        "results": report,
    }


def display(value: Decimal | None, *, percent: bool = False) -> str:
    if value is None:
        return "n/a"
    amount = value * 100 if percent else value
    return str(amount.quantize(D("0.1"), rounding=ROUND_HALF_EVEN))


def render_table(report: dict[str, Any]) -> str:
    period = _report_period(report)
    lines = [
        "# Decision backtest",
        "",
        f"Data kind: **{report['data_kind']}**.",
        f"Ledger coverage: {period} (bounds; synthetic months may be sparse).",
        "",
        "Amounts: 2025 ZAR per hectare per occupied month. Rates are percentages.",
        "",
        "| Default | Decisions | Switch rate | Switch wins | Median gain R | "
        "Median gain % | P10 R | Worst loss R | Median CI90 R |",
        "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | --- |",
    ]
    for name in [crop.value for crop in Crop] + ["pooled"]:
        item = report["results"][name]
        interval = item["median_gain_ci90"]
        ci = "n/a" if interval is None else f"[{display(interval[0])}, {display(interval[1])}]"
        cells = [
            name,
            str(item["decisions"]),
            display(item["switch_rate"], percent=True),
            display(item["switch_win_rate"], percent=True),
            display(item["median_gain_rand"]),
            display(item["median_gain_pct"]),
            display(item["p10_gain_rand"]),
            display(item["worst_loss_rand"]),
            ci,
        ]
        lines.append("| " + " | ".join(cells) + " |")
    lines.extend(
        [
            "",
            "Undefined values and their reasons are recorded in decision_backtest.json.",
            "",
            *[f"- {item}" for item in report["caveats"]],
            "",
        ]
    )
    return "\n".join(lines)


def _report_period(report: dict[str, Any]) -> str:
    """Fail closed for legacy summaries lacking validated ledger coverage."""
    coverage = report.get("coverage")
    kind = report.get("data_kind")
    if not coverage or kind not in {"synthetic", "historical"} or coverage["data_kind"] != kind:
        raise ValueError("report requires validated ledger coverage and matching data kind")
    if kind == "historical" and (
        not coverage["complete_historical_grid"]
        or coverage["start_month"] != HISTORICAL_MONTHS[0].strftime("%Y-%m")
        or coverage["end_month"] != HISTORICAL_MONTHS[-1].strftime("%Y-%m")
        or coverage["observed_months"] != len(HISTORICAL_MONTHS)
        or coverage["decision_keys"] != len(HISTORICAL_KEYS)
        or report.get("information_policy", {}).get("status") != "verified_strictly_before_planting"
    ):
        raise ValueError("insufficient historical coverage or information-cutoff evidence")
    if coverage["start_month"] is None:
        return "no planting months"
    return f"{coverage['start_month']}–{coverage['end_month']}"


def render_sentence(report: dict[str, Any]) -> str:
    period = _report_period(report)
    pooled = report["results"]["pooled"]
    rates = [report["results"][crop.value]["switch_win_rate"] for crop in Crop]
    if pooled["median_gain_rand"] is None or any(rate is None for rate in rates):
        return "INSUFFICIENT EVIDENCE: switch statistics are undefined for one or more defaults.\n"
    prefix = (
        "SYNTHETIC TEST FIXTURE — NOT A REAL RESULT.\n"
        if report["data_kind"] == "synthetic"
        else ""
    )
    return (
        prefix + f"In a historical simulation of {pooled['decisions']} planting decisions "
        f"({period}), using only data available at planting time, when Farmable recommended "
        "switching away from a farmer's usual crop, the switch earned more profit "
        f"{display(pooled['switch_win_rate'], percent=True)}% of the time, with a median "
        f"increase of R {display(pooled['median_gain_rand'])} per hectare per month "
        f"(ranging from {display(min(rates), percent=True)}% to "
        f"{display(max(rates), percent=True)}% across the 8 starting crops). "
        "Assumes guideline yields, Joburg Market prices and Western Cape cost budgets, "
        "adjusted for inflation.\n"
    )


def canonical_json(document: Any) -> bytes:
    def encode(value: Any) -> Any:
        if isinstance(value, Decimal):
            if not value.is_finite():
                raise ValueError("nonfinite report amount")
            return float(value)
        raise TypeError(f"unsupported report value: {type(value).__name__}")

    return (
        json.dumps(
            document, sort_keys=True, ensure_ascii=False, indent=2, allow_nan=False, default=encode
        )
        + "\n"
    ).encode("utf-8")


def write_synthetic_report(report: dict[str, Any], directory: Path) -> str:
    """Exercise serialization only; real publishing requires the future gated runner."""
    if report["data_kind"] != "synthetic":
        raise ValueError("only synthetic fixtures are allowed by this development writer")
    payload = canonical_json(report)
    run_id = hashlib.sha256(payload).hexdigest()
    directory.mkdir(parents=True, exist_ok=False)
    artifacts = {
        "decision_backtest.json": payload,
        "decision_backtest.md": render_table(report).encode("utf-8"),
        "slide_sentence.txt": render_sentence(report).encode("utf-8"),
    }
    for filename, data in artifacts.items():
        (directory / filename).write_bytes(data)
    (directory / "manifest.json").write_bytes(
        canonical_json(
            {
                "run_id": run_id,
                "data_kind": "synthetic",
                "artifacts": {
                    name: hashlib.sha256(data).hexdigest() for name, data in artifacts.items()
                },
            }
        )
    )
    return run_id
