"""Synthetic mutation tests for the strict historical information policy."""

from dataclasses import replace
from datetime import date
from decimal import Decimal as D

import pytest
from farmable_ml.vintage import VersionedValue, select_as_of


def version(
    key: str,
    *,
    effective: date = date(2011, 1, 1),
    available: date = date(2011, 2, 1),
    revision: int = 1,
    value: str = "10",
) -> VersionedValue:
    return VersionedValue(key, effective, available, revision, D(value), "a" * 64)


def test_future_value_and_revision_mutations_do_not_change_as_of_inputs():
    cutoff = date(2012, 1, 1)
    known = version("cabbage_cost")
    future = version("cabbage_cost", available=date(2012, 1, 1), revision=2, value="20")
    first = select_as_of((known, future), cutoff=cutoff, required_keys=frozenset({known.key}))
    mutated = select_as_of(
        (known, replace(future, value=D("999999"))),
        cutoff=cutoff,
        required_keys=frozenset({known.key}),
    )
    assert first == mutated == {known.key: known}


def test_latest_published_revision_at_the_origin_is_selected_deterministically():
    older = version("calendar", available=date(2011, 2, 1), revision=1, value="2")
    newer = version("calendar", available=date(2011, 6, 1), revision=2, value="3")
    selected = select_as_of(
        tuple(reversed((older, newer))),
        cutoff=date(2012, 1, 1),
        required_keys=frozenset({"calendar"}),
    )
    assert selected == {"calendar": newer}


def test_missing_unknown_or_cutoff_day_releases_fail_closed():
    cutoff = date(2012, 1, 1)
    at_cutoff = version("cost", available=cutoff)
    with pytest.raises(ValueError, match="no version"):
        select_as_of((at_cutoff,), cutoff=cutoff, required_keys=frozenset({"cost"}))
    with pytest.raises(ValueError, match="no version"):
        select_as_of((), cutoff=cutoff, required_keys=frozenset({"unknown_release"}))


def test_conflicting_duplicate_vintage_identity_is_rejected():
    row = version("cost")
    with pytest.raises(ValueError, match="duplicate or conflicting"):
        select_as_of(
            (row, replace(row, value=D("11"))),
            cutoff=date(2012, 1, 1),
            required_keys=frozenset({"cost"}),
        )
