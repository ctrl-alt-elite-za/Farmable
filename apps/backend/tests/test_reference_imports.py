"""Reference imports validate first, commit atomically and remain idempotent."""

import json

import pytest
from farmable_backend.models import (
    Base,
    ReferenceCropCalendar,
    ReferenceCropCost,
    ReferenceImport,
    ReferenceMarketPrice,
)
from farmable_backend.reference_cli import read_bundle
from farmable_backend.reference_imports import import_bundle
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import sessionmaker

TABLES = [
    ReferenceImport.__table__,
    ReferenceMarketPrice.__table__,
    ReferenceCropCalendar.__table__,
    ReferenceCropCost.__table__,
]


@pytest.fixture
def sessions():
    engine = create_engine("sqlite+pysqlite:///:memory:")
    Base.metadata.create_all(engine, tables=TABLES)
    yield sessionmaker(engine, expire_on_commit=False)
    engine.dispose()


def payload(kind="market_prices", key="joburg-v1"):
    rows = {
        "market_prices": [
            {
                "crop": "cabbage",
                "market": "joburg",
                "observation_month": "2024-01-01",
                "available_on": "2024-02-01",
                "price_rand_per_kg": "4.2500",
                "availability_kind": "analytical_next_month",
            }
        ],
        "crop_calendars": [
            {
                "crop": "cabbage",
                "region": "western_cape",
                "effective_on": "2025-01-01",
                "available_on": "2025-01-01",
                "revision": 1,
                "planting_months": [1, 2, 3],
                "harvest_offset_months": 3,
                "yield_kg_per_ha": "75000.0000",
                "assumption_kind": "fixed_scenario",
            }
        ],
        "crop_costs": [
            {
                "crop": "cabbage",
                "region": "western_cape",
                "effective_on": "2025-01-01",
                "available_on": "2025-01-01",
                "revision": 1,
                "basis_year": 2025,
                "cost_rand_per_ha": "115183.8500",
                "marketing_rate": "0.125000",
                "vat_basis": "unstated",
            }
        ],
    }
    return json.dumps(
        {
            "schema_version": 1,
            "dataset_kind": kind,
            "dataset_key": key,
            "source_sha256": "a" * 64,
            "source_file": "source.csv",
            "parser_version": 1,
            "rows": rows[kind],
        },
        sort_keys=True,
    ).encode()


@pytest.mark.parametrize("kind", ["market_prices", "crop_calendars", "crop_costs"])
def test_import_idempotent(sessions, kind):
    raw = payload(kind, f"{kind}-v1")
    assert import_bundle(sessions, raw) == ("imported", 1)
    assert import_bundle(sessions, raw) == ("unchanged", 1)
    with sessions() as session:
        assert session.scalar(select(func.count()).select_from(ReferenceImport)) == 1


def test_changed_payload_conflicts_and_invalid_bundle_leaves_no_partial_rows(sessions):
    raw = payload()
    import_bundle(sessions, raw)
    changed = raw.replace(b"4.2500", b"5.2500")
    with pytest.raises(ValueError, match="identity conflict"):
        import_bundle(sessions, changed)
    with pytest.raises(ValueError):
        import_bundle(sessions, b'{"dataset_kind":"market_prices"}')
    with sessions() as session:
        assert session.scalar(select(func.count()).select_from(ReferenceImport)) == 1
        assert session.scalar(select(func.count()).select_from(ReferenceMarketPrice)) == 1


def test_duplicate_natural_keys_rejected_before_transaction(sessions):
    document = json.loads(payload())
    document["rows"].append(document["rows"][0])
    with pytest.raises(ValueError, match="duplicate natural keys"):
        import_bundle(sessions, json.dumps(document).encode())
    with sessions() as session:
        assert session.scalar(select(func.count()).select_from(ReferenceImport)) == 0


def test_cli_reader_rejects_symlinks(tmp_path):
    path = tmp_path / "bundle.json"
    path.write_bytes(payload())
    assert read_bundle(path) == payload()
    link = tmp_path / "link.json"
    try:
        link.symlink_to(path)
    except OSError:
        return
    with pytest.raises(ValueError, match="regular file"):
        read_bundle(link)


def test_source_and_analytical_availability_are_retained(sessions):
    import_bundle(sessions, payload())
    with sessions() as session:
        assert session.scalar(select(ReferenceImport)).source_file == "source.csv"
        assert (
            session.scalar(select(ReferenceMarketPrice)).availability_kind
            == "analytical_next_month"
        )


@pytest.mark.parametrize("available", ["2024-01-15", "2024-03-01"])
def test_invalid_analytical_date_rejected(sessions, available):
    document = json.loads(payload())
    document["rows"][0]["available_on"] = available
    with pytest.raises(ValueError):
        import_bundle(sessions, json.dumps(document).encode())


def test_natural_key_conflict_rolls_back_entire_bundle(sessions):
    import_bundle(sessions, payload())
    document = json.loads(payload(key="different-source"))
    document["rows"].insert(0, {**document["rows"][0], "crop": "carrots"})
    with pytest.raises(ValueError, match="natural key conflict"):
        import_bundle(sessions, json.dumps(document).encode())
    with sessions() as session:
        assert session.scalar(select(func.count()).select_from(ReferenceImport)) == 1
        assert session.scalar(select(func.count()).select_from(ReferenceMarketPrice)) == 1


def test_concurrent_identical_imports_are_noops(tmp_path):
    from concurrent.futures import ThreadPoolExecutor
    from threading import Barrier

    engine = create_engine(f"sqlite+pysqlite:///{tmp_path / 'reference.db'}")
    Base.metadata.create_all(engine, tables=TABLES)
    factory = sessionmaker(engine)
    barrier = Barrier(4)

    def run(_):
        barrier.wait(timeout=10)
        return import_bundle(factory, payload())

    try:
        with ThreadPoolExecutor(max_workers=4) as pool:
            results = list(pool.map(run, range(4)))
        assert results.count(("imported", 1)) == 1
        assert results.count(("unchanged", 1)) == 3
    finally:
        engine.dispose()
