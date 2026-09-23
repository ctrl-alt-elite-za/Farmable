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
farm, including ones created by an earlier run of this command -- but only
across sequential runs. `farms(owner_id)` has no unique constraint, and a
`FOR UPDATE` lock on the candidate identity rows would not help here: the
conflicting write is an INSERT into `farms`, not a modification of the
locked identity row, so two runs launched close enough together would both
read the same ownerless set and both insert. A session-scoped Postgres
advisory lock (skipped on SQLite, which has none, for the unit suite) makes
overlapping invocations run one at a time instead.
"""

from sqlalchemy import func, select
from sqlalchemy.orm import Session

from farmable_backend.auth import DEFAULT_FARM_NAME
from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.models import AuthIdentity, Farm

# Arbitrary fixed key identifying this command's advisory lock. Any int64
# works; it only needs to be stable and not collide with another command's.
_BACKFILL_LOCK_KEY = 747_100_009


def backfill_account_farms(session: Session) -> int:
    """Create one default farm per identity that has none. Returns the count."""
    if session.bind is not None and session.bind.dialect.name == "postgresql":
        # Blocks here until any concurrently-running invocation commits or
        # rolls back, so the check-and-insert below never races another copy
        # of this same command. Released automatically at transaction end.
        session.execute(select(func.pg_advisory_xact_lock(_BACKFILL_LOCK_KEY)))
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
