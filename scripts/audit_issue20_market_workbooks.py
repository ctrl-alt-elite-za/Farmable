"""Read-only source coverage audit; never assigns historical availability dates.

Run with temporary readers: uv run --with xlrd==2.0.2 --with openpyxl==3.1.5
python scripts/audit_issue20_market_workbooks.py PATH/TO/downloads.json
The manifest lists filename, year, URL, retrieval date and SHA-256 for local files.
"""

import argparse
import hashlib
import json
import math
import re
from pathlib import Path

ALIASES = {
    "butternut": "BUTTERNUT SQUASHES",
    "cabbage": "CABBAGE",
    "carrots": "CARROTS",
    "green_beans": "GREEN BEANS",
    "onions": "ONIONS",
    "potatoes": "POTATOES",
    "spinach": "SPINACH",
    "tomatoes": "TOMATOES",
}


def json_payload(document: dict) -> str:
    """Render stable readable JSON without expanding short integer arrays."""

    payload = json.dumps(document, indent=2)

    def compact(match: re.Match) -> str:
        return "[" + ", ".join(re.findall(r"\d+", match.group(0))) + "]"

    return re.sub(r"\[\n(?:\s+\d+,?\n)+\s+\]", compact, payload) + "\n"


def read_sheet(path: Path) -> tuple[str, list[list]]:
    if path.suffix.lower() == ".xls":
        import xlrd

        book = xlrd.open_workbook(path)
        names = book.sheet_names()
        name = next(name for name in names if name.strip().upper() == "T6 JHB")
        sheet = book.sheet_by_name(name)
        return name, [sheet.row_values(i) for i in range(sheet.nrows)]
    import openpyxl

    book = openpyxl.load_workbook(path, read_only=True, data_only=True)
    try:
        name = next(name for name in book.sheetnames if name.strip().upper() == "T6 JHB")
        return name, [list(row) for row in book[name].values]
    finally:
        book.close()


def audit_rows(rows: list[list], year: int) -> dict:
    title = " ".join(str(cell) for row in rows[:5] for cell in row if cell)
    if "JOHANNESBURG" not in title or str(year) not in title:
        raise ValueError("wrong market/year title")
    header = next(row for row in rows[:10] if "PRODUCT" in row)
    start = header.index("J")
    if header[start : start + 12] != list("JFMAMJJASOND"):
        raise ValueError("unexpected monthly columns")
    result = {}
    for crop, alias in ALIASES.items():
        matches = [
            (i, j)
            for i, row in enumerate(rows)
            for j, cell in enumerate(row[:start])
            if re.sub(r"^\s*\d+\.\s*", "", str(cell)).strip() == alias
        ]
        if len(matches) != 1:
            raise ValueError(f"expected exactly one {alias} product row")
        i, j = matches[0]
        # 2020/2021 place the product label on the mass row, others on value.
        if str(rows[i][j + 1]).strip() == "T":
            i += 1
        if [str(rows[r][j + 1]).strip() for r in (i - 1, i, i + 1)] != ["T", "R", "R/T"]:
            raise ValueError(f"unexpected mass/value/price units for {crop}")
        valid, missing, inconsistent = [], [], []
        for month, column in enumerate(range(start, start + 12), 1):
            mass, value, price = (rows[r][column] for r in (i - 1, i, i + 1))
            if not all(
                isinstance(v, int | float) and math.isfinite(v) and v > 0
                for v in (mass, value, price)
            ):
                missing.append(month)
            elif not math.isclose(value / mass, price, rel_tol=1e-6, abs_tol=0.01):
                inconsistent.append(month)
            else:
                valid.append(month)
        result[crop] = {
            "source_label": alias,
            "price_row": i + 2,
            "valid_months": valid,
            "missing_or_nonpositive_months": missing,
            "inconsistent_price_months": inconsistent,
        }
    return result


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    records = []
    manifest = json.loads(args.manifest.read_text())
    sources = manifest["sources"] if isinstance(manifest, dict) else manifest
    for source in sorted(sources, key=lambda item: item["year"]):
        record = dict(source)
        try:
            path = args.manifest.parent / source["filename"]
            if hashlib.sha256(path.read_bytes()).hexdigest() != source["sha256"]:
                raise ValueError("source hash mismatch")
            sheet, rows = read_sheet(path)
            record.update(sheet=sheet, crops=audit_rows(rows, int(source["year"])))
        except (KeyError, ValueError, StopIteration) as exc:
            record["audit_error"] = str(exc) or "expected sheet/header missing"
        record.update(
            available_on=None,
            availability_status="unknown_blocks_historical_use",
            availability_evidence=(
                "The official archive exposes the annual file but no historical "
                "publication or revision date. Observation labels, retrieval time and "
                "file metadata are not release evidence."
            ),
            redistribution_status="unverified",
        )
        records.append(record)
    payload = json_payload(
        {
            "parser_version": 1,
            "status": "not_approved_for_historical_features",
            "sources": records,
        }
    )
    if args.output:
        args.output.write_text(payload, encoding="utf-8")
    else:
        print(payload, end="")


if __name__ == "__main__":
    main()
