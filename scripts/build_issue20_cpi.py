"""Rebuild monthly CPI bytes from the attributed Stats SA Table B1 transcription."""

import csv
import hashlib
import io
import re
from pathlib import Path


def build(source: str) -> bytes:
    buffer = io.StringIO(newline="")
    writer = csv.writer(buffer, lineterminator="\n")
    writer.writerow(("observation_month", "index_dec2024_100"))
    years = set()
    for line in source.splitlines():
        if not re.match(r"^\d{4} ", line):
            continue
        fields = line.split()
        year = int(fields[0])
        if year in years or len(fields) != 14:
            raise ValueError("expected one year, twelve months and an annual average")
        if any(not re.fullmatch(r"\d+\.\d", value) for value in fields[1:]):
            raise ValueError("expected the source's one-decimal index levels")
        years.add(year)
        for month, value in enumerate(fields[1:13], start=1):
            writer.writerow((f"{year}-{month:02d}-01", value))
    if years != set(range(2000, 2026)):
        raise ValueError("expected all years 2000 through 2025")
    return buffer.getvalue().encode("utf-8")


if __name__ == "__main__":
    root = Path(__file__).resolve().parents[1]
    source = root / "ml/data/statssa_cpi_table_b1.txt"
    target = root / "ml/data/cpi_za_monthly.csv"
    data = build(source.read_text(encoding="utf-8"))
    target.write_bytes(data)
    for path in (source, target):
        print(f"{path.name}: {hashlib.sha256(path.read_bytes()).hexdigest()}")
