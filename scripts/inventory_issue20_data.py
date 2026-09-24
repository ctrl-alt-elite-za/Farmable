#!/usr/bin/env python3
"""Inventory issue #20 staged CSVs without checking out or copying them.

The command reads blobs directly from a Git ref.  It is intentionally stdlib-only
so that it can be run before the ML package exists and in a credential-free
environment.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import json
import re
import shutil
import subprocess
from pathlib import Path
from typing import Any

ISSUE_CROPS = (
    "butternut",
    "cabbage",
    "carrots",
    "green_beans",
    "onions",
    "potatoes",
    "spinach",
    "tomatoes",
)


def git(repo: Path, *args: str) -> bytes:
    executable = shutil.which("git")
    if executable is None:
        raise RuntimeError("git executable is not available on PATH")
    result = subprocess.run(  # noqa: S603 - resolved git executable, no shell
        [executable, "-C", str(repo), *args],
        check=True,
        capture_output=True,
    )
    return result.stdout


def canonical_crop(value: str) -> str:
    value = value.strip().lower().replace("-", " ")
    aliases = {
        "cabbages": "cabbage",
        "carrot": "carrots",
        "green beans": "green_beans",
        "onion": "onions",
        "potato": "potatoes",
        "tomato": "tomatoes",
    }
    return aliases.get(value, value.replace(" ", "_"))


def nonempty(value: str | None) -> bool:
    return value is not None and value.strip() != ""


def parse_date(value: str) -> str | None:
    value = value.strip()
    if re.fullmatch(r"\d{4}-\d{2}-\d{2}", value):
        return value
    if re.fullmatch(r"\d{4}-\d{2}", value):
        return value
    return None


def inventory_csv(path: str, blob: bytes) -> dict[str, Any]:
    text = blob.decode("utf-8-sig")
    reader = csv.DictReader(io.StringIO(text, newline=""))
    columns = reader.fieldnames or []
    rows = list(reader)
    if len(columns) != len(set(columns)):
        raise ValueError(f"{path}: duplicate CSV columns")
    if any(None in row or any(value is None for value in row.values()) for row in rows):
        raise ValueError(f"{path}: inconsistent CSV row width")
    lower_columns = {column.lower().strip(): column for column in columns}

    crop_column = next(
        (
            lower_columns[name]
            for name in ("crop", "commodity", "item", "item_faostat")
            if name in lower_columns
        ),
        None,
    )
    crop_values = sorted(
        {row[crop_column].strip() for row in rows if crop_column and nonempty(row.get(crop_column))}
    )
    canonical_values = sorted({canonical_crop(value) for value in crop_values})
    present = sorted(set(canonical_values).intersection(ISSUE_CROPS))

    coverage: dict[str, Any] = {}
    date_column = next(
        (lower_columns[name] for name in ("date", "date_scraped") if name in lower_columns),
        None,
    )
    if date_column:
        dates = sorted(
            parsed
            for parsed in (parse_date(row.get(date_column, "")) for row in rows)
            if parsed is not None
        )
        if dates:
            coverage.update(
                {
                    "date_column": date_column,
                    "min": dates[0],
                    "max": dates[-1],
                    "unique_values": len(set(dates)),
                }
            )

    year_column = lower_columns.get("year")
    month_column = lower_columns.get("month_num")
    if year_column:
        years = sorted(
            {
                row[year_column].strip()
                for row in rows
                if re.fullmatch(r"\d{4}", row.get(year_column, "").strip())
            }
        )
        coverage["year_column"] = year_column
        if years:
            coverage.update(
                {
                    "min_year": int(years[0]),
                    "max_year": int(years[-1]),
                    "years": [int(year) for year in years],
                }
            )
        if month_column:
            months = sorted(
                {
                    row[month_column].strip()
                    for row in rows
                    if row.get(month_column, "").strip().isdigit()
                }
            )
            coverage["month_column"] = month_column
            coverage["months"] = [int(month) for month in months]

    wide_years: dict[int, int] = {}
    for column in columns:
        match = re.fullmatch(r"Y(\d{4})", column)
        if match:
            year = int(match.group(1))
            wide_years[year] = sum(1 for row in rows if nonempty(row.get(column)))
    if wide_years:
        available_years = sorted(year for year, count in wide_years.items() if count)
        coverage["wide_year_columns"] = {
            "min_year_with_values": available_years[0] if available_years else None,
            "max_year_with_values": available_years[-1] if available_years else None,
            "nonempty_rows_by_year": {str(year): wide_years[year] for year in sorted(wide_years)},
        }

    limitations, provenance = source_notes(path)
    return {
        "path": path,
        "sha256": hashlib.sha256(blob).hexdigest(),
        "bytes": len(blob),
        "rows": len(rows),
        "columns": columns,
        "crop_column": crop_column,
        "crop_values": crop_values,
        "issue20_crops_present": present,
        "issue20_crops_missing": sorted(set(ISSUE_CROPS).difference(present)),
        "coverage": coverage,
        "provenance": provenance,
        "availability_limitations": limitations,
    }


def source_notes(path: str) -> tuple[list[str], dict[str, str]]:
    if "/joburg_market/" in path:
        return [
            "The staged CSV is a scraper output, not a source-published historical archive.",
            "README reports 41 days; 2012-2024 coverage is not established.",
            "Release dates, grade/package normalization and redistribution terms are absent.",
            "Value divided by kg yields a daily weighted price, not a canonical monthly price.",
        ], {
            "source": "Joburg Market daily prices via sa-fresh-produce-market-analysis scraper",
            "source_url": "https://joburgmarket.co.za/jhb-market/dailyprices.php",
        }
    if "/faostat_producer_prices/" in path:
        return [
            "FAOSTAT producer prices are farm-gate/producer prices, not Joburg wholesale prices.",
            "FAOSTAT download date, vintage and publication dates are absent.",
            "Raw rows mix annual/monthly elements and flags; header years do not prove coverage.",
        ], {
            "source": "FAOSTAT South Africa producer prices",
            "source_url": "https://www.fao.org/faostat/en/#data/PP",
        }
    if "/crop_calendar/" in path:
        return [
            "README attributes this table to GDARD vegetable guidelines and ARC green beans.",
            "URL, retrieval date, version, region and redistribution terms are absent.",
            "Planting windows/durations are scenario inputs, not historical farming evidence.",
        ], {
            "source": "GDARD vegetable guidelines; ARC Growing Green Beans (README attribution)",
            "source_url": "",
        }
    if "/rainfall/" in path:
        return [
            "README names Open-Meteo; API query, coordinates and retrieval metadata are absent.",
            "Regional rainfall cannot substitute for crop-specific market price history.",
        ], {"source": "Open-Meteo historical weather API", "source_url": "https://open-meteo.com/"}
    return ["No source metadata was recorded for this file."], {
        "source": "unknown",
        "source_url": "",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--ref", default="origin/issue-20-reference-data")
    parser.add_argument("--repo", default=".", type=Path)
    args = parser.parse_args()

    repo = args.repo.resolve()
    commit = (
        git(repo, "rev-parse", "--verify", "--end-of-options", f"{args.ref}^{{commit}}")
        .decode()
        .strip()
    )
    paths = [
        path
        for path in git(repo, "ls-tree", "-r", "--name-only", commit, "--", "ml/data")
        .decode()
        .splitlines()
        if path.lower().endswith(".csv")
    ]
    files = []
    for path in sorted(paths):
        files.append(inventory_csv(path, git(repo, "cat-file", "blob", f"{commit}:{path}")))

    document = {
        "schema_version": 1,
        "ref": args.ref,
        "commit": commit,
        "files": files,
        "issue20_crops": list(ISSUE_CROPS),
        "limitations": [
            "Blob contents/hashes do not prove historical source availability or licensing.",
            "No real forecast or decision backtest is run by this command.",
        ],
    }
    print(json.dumps(document, ensure_ascii=False, indent=2, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
