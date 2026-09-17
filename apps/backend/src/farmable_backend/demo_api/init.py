"""Explicitly initialize the isolated prototype store (never the production DB)."""

import os
from pathlib import Path

from .storage import initialize_storage


def database_path() -> Path:
    return Path(os.getenv("FARMABLE_DEMO_DB", ".farmable-demo/state.sqlite3")).resolve()


def main() -> None:
    initialize_storage(database_path())
    print("Initialized local synthetic-data demo storage. Not production readiness.")


if __name__ == "__main__":
    main()
