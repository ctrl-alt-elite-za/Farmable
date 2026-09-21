"""Explicit, repeatable production-schema demo seed command."""

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.demo_seed import seed_demo_farm


def main() -> None:
    database = Database(Settings())
    try:
        with database.sessions.begin() as session:
            farm = seed_demo_farm(session)
            print(f"demo farm ready: {farm.id}")
    finally:
        database.close()


if __name__ == "__main__":
    main()
