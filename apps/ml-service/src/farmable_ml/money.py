"""Explicit-unit arithmetic. This module does not choose historical scenario inputs.

The CPI helper is for retrospective reporting only. Passing its outputs into a
historical recommendation requires a separately resolved information contract.
"""

from decimal import ROUND_HALF_EVEN, Context, Decimal, localcontext


def _validate(value: Decimal, field: str, *, positive: bool = False) -> None:
    if not isinstance(value, Decimal) or not value.is_finite():
        raise ValueError(f"{field} must be a finite Decimal")
    if value < 0 or (positive and value == 0):
        raise ValueError(f"{field} is outside its allowed range")


def gross_margin(
    *,
    price_rand_per_kg: Decimal,
    yield_kg_per_ha: Decimal,
    cost_rand_per_ha: Decimal,
    occupied_months: Decimal,
) -> Decimal:
    """Return rand/ha/month; caller must supply prices/costs in the same basis."""
    _validate(price_rand_per_kg, "price_rand_per_kg")
    _validate(yield_kg_per_ha, "yield_kg_per_ha", positive=True)
    _validate(cost_rand_per_ha, "cost_rand_per_ha")
    _validate(occupied_months, "occupied_months", positive=True)
    with localcontext(Context(prec=28, rounding=ROUND_HALF_EVEN)):
        return (price_rand_per_kg * yield_kg_per_ha - cost_rand_per_ha) / occupied_months


def reporting_value(
    nominal_value: Decimal, *, observation_cpi: Decimal, reporting_cpi: Decimal
) -> Decimal:
    """Convert a signed retrospective amount using explicit positive index levels."""
    if not isinstance(nominal_value, Decimal) or not nominal_value.is_finite():
        raise ValueError("nominal_value must be a finite Decimal")
    _validate(observation_cpi, "observation_cpi", positive=True)
    _validate(reporting_cpi, "reporting_cpi", positive=True)
    with localcontext(Context(prec=28, rounding=ROUND_HALF_EVEN)):
        return nominal_value * reporting_cpi / observation_cpi
