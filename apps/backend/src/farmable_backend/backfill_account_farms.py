"""Explicit, repeatable backfill of the one-farm-per-account invariant (#9).

`AuthService.signup` creates a farm for every new account, but accounts that
signed up before that shipped have none, so `/account/farm` 404s for them
forever. This command gives each such account the same default farm sign-up
would have.

Owners are enumerated from `auth_identities`, not `users`: `delete_account`
keeps the users row as a foreign-key referent while removing the identity and
tombstoning the farm, so enumerating users would resurrect a live farm for
every deleted account.

Idempotent: the anti-join already excludes any owner holding a non-deleted
farm, including ones created by an earlier run of this command.
"""

from sqlalchemy import select
from sqlalchemy.orm import Session

from farmable_backend.auth import DEFAULT_FARM_NAME
from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.models import AuthIdentity, Farm


def backfill_account_farms(session: Session) -> int:
    """Create one default farm per identity that has none. Returns the count."""
    owned = select(Farm.owner_id).where(Farm.deleted_at.is_(None))
    owners = session.scalars(
        select(AuthIdentity.id).where(AuthIdentity.id.not_in(owned)).order_by(AuthIdentity.id)
    ).all()
    for owner in owners:
        session.add(Farm(owner_id=owner, name=DEFAULT_FARM_NAME))
    session.flush()
    return len(owners)


def main() -> None:
    database = Database(Settings())
    try:
        with database.sessions.begin() as session:
            created = backfill_account_farms(session)
            print(f"account farms backfilled: {created}")
    finally:
        database.close()


if __name__ == "__main__":
    main()
