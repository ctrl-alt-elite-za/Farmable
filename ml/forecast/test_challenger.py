"""Real LightGBM fits on synthetic seasonal observations."""

from dataclasses import replace
from datetime import date
from decimal import Decimal as D

from farmable_ml.challenger import lightgbm_quantiles
from farmable_ml.data import Crop, PriceObservation
from farmable_ml.forecast import shift_month


def test_lightgbm_future_mutation_and_repeatability():
    rows = tuple(
        PriceObservation(
            Crop.CABBAGE,
            "synthetic",
            month,
            shift_month(month, 1).replace(day=15),
            D(10 + month.month),
            "a" * 64,
        )
        for month in (shift_month(date(2000, 1, 1), offset) for offset in range(96))
    )
    origin = date(2006, 1, 1)
    changed = tuple(
        replace(row, price_rand_per_kg=D("99999")) if row.available_on >= origin else row
        for row in rows
    )
    args = dict(crop=Crop.CABBAGE, market="synthetic", origin=origin, target=date(2006, 6, 1))
    before = lightgbm_quantiles(rows, **args)
    assert before == lightgbm_quantiles(changed, **args)
    assert before == lightgbm_quantiles(rows, **args)
    assert 0 < before.p10 <= before.p50 <= before.p90
