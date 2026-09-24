"""Versioned Parquet export compatible with #21's normalized JSON fixture seam.

Month numbers refer to planting, and prices to the subsequent harvest. Both
formats explicitly retain 2025 ZAR/kg and synthetic/historical labels.
"""

import json
import re
from datetime import datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

import pyarrow as pa
import pyarrow.parquet as pq

from farmable_ml.data import Crop
from farmable_ml.reports import canonical_json

AMOUNT = pa.decimal128(14, 4)
SCHEMA = pa.schema(
    [
        pa.field("crop", pa.string(), nullable=False),
        pa.field("plant_month", pa.int8(), nullable=False),
        pa.field("growing_months", pa.int8(), nullable=False),
        *[pa.field(name, AMOUNT, nullable=False) for name in ("p10", "p50", "p90")],
        pa.field("method", pa.string(), nullable=False),
        pa.field("cost_per_ha", AMOUNT, nullable=False),
        pa.field("yield_kg_per_ha", AMOUNT, nullable=False),
    ]
)
METADATA_KEY = b"farmable.snapshot.v1"
FIELDS = set(SCHEMA.names)
META_FIELDS = {
    "schema_version",
    "run_id",
    "data_kind",
    "as_of",
    "currency",
    "price_basis_year",
    "sources",
    "assumptions",
}


def validate_bundle(bundle: dict[str, Any]) -> None:
    if set(bundle) != META_FIELDS | {"rows"}:
        raise ValueError("unexpected snapshot fields")
    if type(bundle["schema_version"]) is not int or bundle["schema_version"] != 1:
        raise ValueError("unsupported schema_version")
    if (
        bundle["currency"] != "ZAR"
        or type(bundle["price_basis_year"]) is not int
        or bundle["price_basis_year"] != 2025
    ):
        raise ValueError("snapshot requires 2025 ZAR/kg")
    if not isinstance(bundle["run_id"], str) or not re.fullmatch(
        r"[a-z0-9][a-z0-9_-]{0,63}", bundle["run_id"]
    ):
        raise ValueError("invalid run_id")
    if bundle["data_kind"] not in {"synthetic", "historical", "retrospective"}:
        raise ValueError("invalid data_kind")
    as_of = datetime.fromisoformat(bundle["as_of"])
    if as_of.tzinfo is None:
        raise ValueError("as_of requires timezone")
    sources = bundle["sources"]
    if not isinstance(sources, list) or not 1 <= len(sources) <= 32:
        raise ValueError("snapshot requires sources")
    names = set()
    for source in sources:
        if (
            set(source) != {"name", "sha256"}
            or not re.fullmatch(r"[a-zA-Z0-9_.-]{1,100}", source["name"])
            or not re.fullmatch(r"[0-9a-f]{64}", source["sha256"])
        ):
            raise ValueError("invalid source hash")
        if source["name"] in names:
            raise ValueError("duplicate source name")
        names.add(source["name"])
    assumptions = bundle["assumptions"]
    if (
        not isinstance(assumptions, list)
        or not 1 <= len(assumptions) <= 32
        or any(not isinstance(item, str) or not 1 <= len(item) <= 1000 for item in assumptions)
    ):
        raise ValueError("snapshot requires explicit assumptions")
    rows = bundle["rows"]
    if not isinstance(rows, list) or len(rows) != 96:
        raise ValueError("snapshot requires exactly 96 crop/month rows")
    keys = set()
    for row in rows:
        if set(row) != FIELDS:
            raise ValueError("unexpected row fields")
        crop = Crop(row["crop"])
        for field in ("plant_month", "growing_months"):
            if type(row[field]) is not int or not 1 <= row[field] <= 12:
                raise ValueError(f"{field} must be an integer in 1..12")
        key = (crop.value, row["plant_month"])
        if key in keys:
            raise ValueError("duplicate crop/month")
        keys.add(key)
        for field in ("p10", "p50", "p90", "cost_per_ha", "yield_kg_per_ha"):
            value = row[field]
            if not isinstance(value, Decimal) or not value.is_finite() or value <= 0:
                raise ValueError(f"{field} must be a positive finite Decimal")
            if value >= Decimal("10000000000") or value != value.quantize(Decimal("0.0001")):
                raise ValueError(f"{field} exceeds decimal(14,4)")
        if not row["p10"] <= row["p50"] <= row["p90"]:
            raise ValueError("crossed quantiles")
        methods = (
            {"fixture"} if bundle["data_kind"] == "synthetic" else {"historical_range", "lightgbm"}
        )
        if row["method"] not in methods:
            raise ValueError("method incompatible with data_kind")
    if keys != {(crop.value, month) for crop in Crop for month in range(1, 13)}:
        raise ValueError("incomplete crop/month grid")


def write_snapshot(bundle: dict[str, Any], path: Path) -> None:
    validate_bundle(bundle)
    metadata = {key: bundle[key] for key in sorted(META_FIELDS)}
    rows = sorted(bundle["rows"], key=lambda row: (row["crop"], row["plant_month"]))
    table = pa.Table.from_pylist(rows, schema=SCHEMA).replace_schema_metadata(
        {METADATA_KEY: canonical_json(metadata)}
    )
    pq.write_table(
        table,
        path,
        version="2.6",
        compression="NONE",
        use_dictionary=False,
        write_statistics=True,
        data_page_version="1.0",
        row_group_size=96,
    )


def read_snapshot(path: Path) -> dict[str, Any]:
    if path.stat().st_size > 1024 * 1024:
        raise ValueError("snapshot exceeds 1 MiB limit")
    parquet = pq.ParquetFile(path)
    if parquet.metadata.num_rows != 96:
        raise ValueError("snapshot requires exactly 96 rows")
    if not parquet.schema_arrow.remove_metadata().equals(SCHEMA):
        raise ValueError("unexpected Parquet schema")
    metadata = parquet.schema_arrow.metadata or {}
    if METADATA_KEY not in metadata:
        raise ValueError("snapshot metadata missing")
    bundle = json.loads(metadata[METADATA_KEY])
    if not isinstance(bundle, dict) or set(bundle) != META_FIELDS:
        raise ValueError("unexpected snapshot metadata")
    bundle["rows"] = parquet.read().to_pylist()
    validate_bundle(bundle)
    return bundle


def consumer_json(bundle: dict[str, Any]) -> bytes:
    """#21 uses strings for Decimal amounts; preserve all four places exactly."""
    validate_bundle(bundle)
    result = {key: bundle[key] for key in META_FIELDS}
    result["rows"] = [
        {
            key: format(value, ".4f") if isinstance(value, Decimal) else value
            for key, value in row.items()
        }
        for row in sorted(bundle["rows"], key=lambda row: (row["crop"], row["plant_month"]))
    ]
    return canonical_json(result)
