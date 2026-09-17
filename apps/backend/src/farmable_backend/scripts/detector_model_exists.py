"""Check that a detector version is registered in the ORM."""

from __future__ import annotations

import argparse

from sqlalchemy import select

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.models import DetectorModel


def exists(version: str, database: Database) -> bool:
    with database.sessions() as session:
        statement = select(DetectorModel.id).where(DetectorModel.version == version)
        return session.scalar(statement) is not None


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("version")
    args = parser.parse_args()
    database = Database(Settings())
    try:
        return 0 if exists(args.version, database) else 1
    finally:
        database.close()


if __name__ == "__main__":
    raise SystemExit(main())
