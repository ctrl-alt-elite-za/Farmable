"""Strict as-of selection for versioned costs, calendars and other inputs."""

import re
from dataclasses import dataclass
from datetime import date
from decimal import Decimal


@dataclass(frozen=True)
class VersionedValue:
    """One source version with separate effective and public-availability dates."""

    key: str
    effective_on: date
    available_on: date
    revision: int
    value: Decimal
    source_sha256: str

    def __post_init__(self) -> None:
        if not self.key.strip() or self.key != self.key.strip():
            raise ValueError("versioned input key must be nonempty and trimmed")
        if self.revision < 1:
            raise ValueError("revision must be positive")
        if not isinstance(self.value, Decimal) or not self.value.is_finite():
            raise ValueError("versioned input value must be a finite Decimal")
        if not re.fullmatch(r"[0-9a-f]{64}", self.source_sha256):
            raise ValueError("source_sha256 must be a lowercase SHA-256 digest")


def select_as_of(
    records: tuple[VersionedValue, ...],
    *,
    cutoff: date,
    required_keys: frozenset[str],
) -> dict[str, VersionedValue]:
    """Select the latest effective version released strictly before a cutoff.

    Unknown release dates cannot be represented. A revision published at the
    planting cutoff is future information. Conflicting copies of the same source
    identity fail instead of using input order as a last-row-wins rule.
    """
    if cutoff.day != 1:
        raise ValueError("planting cutoff must be the first day of a month")
    if not required_keys or any(not key.strip() or key != key.strip() for key in required_keys):
        raise ValueError("required_keys must contain nonempty trimmed identifiers")
    identities: dict[tuple[str, date, date, int], VersionedValue] = {}
    for record in records:
        identity = (record.key, record.effective_on, record.available_on, record.revision)
        if identity in identities:
            raise ValueError("duplicate or conflicting versioned input identity")
        identities[identity] = record
    selected = {}
    for key in sorted(required_keys):
        eligible = [
            record
            for record in records
            if record.key == key and record.effective_on <= cutoff and record.available_on < cutoff
        ]
        if not eligible:
            raise ValueError(f"no version of {key!r} was available before planting")
        selected[key] = max(
            eligible,
            key=lambda record: (record.effective_on, record.available_on, record.revision),
        )
    return selected
