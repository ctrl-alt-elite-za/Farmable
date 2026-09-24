"""Synthetic arithmetic tests; no real experiment or committed CPI acceptance claim."""

from decimal import Decimal, localcontext

import pytest
from farmable_ml.money import gross_margin, reporting_value

D = Decimal


def test_gross_margin_formula():
    assert gross_margin(
        price_rand_per_kg=D("5"),
        yield_kg_per_ha=D("20000"),
        cost_rand_per_ha=D("40000"),
        occupied_months=D("2.5"),
    ) == D("24000")


def test_negative_margin_is_preserved():
    assert gross_margin(
        price_rand_per_kg=D("1"),
        yield_kg_per_ha=D("10000"),
        cost_rand_per_ha=D("40000"),
        occupied_months=D("3"),
    ) == D("-10000")


@pytest.mark.parametrize("duration", ["0", "-1", "NaN", "Infinity"])
def test_invalid_occupation_rejected(duration):
    with pytest.raises(ValueError):
        gross_margin(
            price_rand_per_kg=D("5"),
            yield_kg_per_ha=D("20000"),
            cost_rand_per_ha=D("40000"),
            occupied_months=D(duration),
        )


def test_reporting_conversion_preserves_losses_and_base_identity():
    assert reporting_value(D("-50"), observation_cpi=D("100"), reporting_cpi=D("150")) == D("-75")
    assert reporting_value(D("50"), observation_cpi=D("150"), reporting_cpi=D("150")) == D("50")


def test_calculation_does_not_inherit_callers_decimal_precision():
    with localcontext() as context:
        context.prec = 2
        assert reporting_value(D("1234.56"), observation_cpi=D("100"), reporting_cpi=D("150")) == D(
            "1851.84"
        )


@pytest.mark.parametrize("index", ["0", "-1", "NaN", "Infinity"])
def test_invalid_reporting_index_rejected(index):
    with pytest.raises(ValueError):
        reporting_value(D("10"), observation_cpi=D(index), reporting_cpi=D("100"))


def test_future_cpi_cost_conversion_can_change_ranking():
    """Regression evidence for the unresolved protocol, not an accepted decision rule."""

    def margins(future_cpi):
        costs = [
            reporting_value(cost, observation_cpi=future_cpi, reporting_cpi=D("100"))
            for cost in (D("120"), D("40"))
        ]
        return [revenue - cost for revenue, cost in zip((D("100"), D("70")), costs, strict=False)]

    a, b = margins(D("200"))
    assert a < b
    a, b = margins(D("400"))
    assert a > b
