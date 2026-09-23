"""CPU LightGBM quantiles with features reconstructed at each training origin."""

import math
from datetime import date
from decimal import Decimal

import lightgbm as lgb
import numpy as np

from farmable_ml.data import Crop, PriceObservation
from farmable_ml.forecast import QUANTILES, Forecast, InsufficientHistory, _history, shift_month


def features(
    records: tuple[PriceObservation, ...],
    *,
    crop: Crop,
    market: str,
    origin: date,
    target: date,
) -> list[float]:
    lookup = {
        row.observation_month: row.price_rand_per_kg
        for row in _history(records, crop, market, origin)
    }
    months = [shift_month(origin, -offset) for offset in (2, 3, 4, 6, 12)]
    if any(month not in lookup for month in months):
        raise InsufficientHistory("missing required lag observations")
    lagged = [float(lookup[month]) for month in months]
    horizon = (target.year - origin.year) * 12 + target.month - origin.month
    if not 0 <= horizon <= 12:
        raise ValueError("supported horizon is 0..12 months")
    return [
        math.sin(2 * math.pi * target.month / 12),
        math.cos(2 * math.pi * target.month / 12),
        float(horizon),
        *lagged,
    ]


def lightgbm_quantiles(
    records: tuple[PriceObservation, ...],
    *,
    crop: Crop,
    market: str,
    origin: date,
    target: date,
    minimum_training_rows: int = 36,
) -> Forecast:
    if minimum_training_rows < 2:
        raise ValueError("minimum_training_rows must be at least two")
    horizon = (target.year - origin.year) * 12 + target.month - origin.month
    prediction_features = features(records, crop=crop, market=market, origin=origin, target=target)
    x, y = [], []
    # Labels themselves must be published before the current fit. Features for
    # each label are rebuilt at that label's own historical planting cutoff.
    for row in sorted(_history(records, crop, market, origin), key=lambda r: r.observation_month):
        historical_origin = shift_month(row.observation_month, -horizon)
        try:
            values = features(
                records,
                crop=crop,
                market=market,
                origin=historical_origin,
                target=row.observation_month,
            )
        except InsufficientHistory:
            continue
        x.append(values)
        y.append(float(row.price_rand_per_kg))
    if len(x) < minimum_training_rows:
        raise InsufficientHistory("insufficient complete lagged training rows")
    output = []
    for q in QUANTILES:
        model = lgb.train(
            {
                "objective": "quantile",
                "alpha": float(q),
                "verbosity": -1,
                "deterministic": True,
                "force_col_wise": True,
                "num_threads": 1,
                "seed": 20,
                "data_random_seed": 20,
                "feature_fraction_seed": 20,
                "bagging_seed": 20,
                "num_leaves": 7,
                "min_data_in_leaf": 10,
                "learning_rate": 0.05,
                "device_type": "cpu",
            },
            lgb.Dataset(np.asarray(x, dtype=np.float64), label=np.asarray(y, dtype=np.float64)),
            num_boost_round=50,
        )
        value = float(model.predict(np.asarray([prediction_features]), num_threads=1)[0])
        if not math.isfinite(value) or value <= 0:
            raise InsufficientHistory("LightGBM returned a nonpositive or nonfinite price")
        output.append(Decimal(str(value)))
    # Fixed monotone rearrangement, used identically for evaluation and export.
    return Forecast(crop, origin, target, "lightgbm", *sorted(output))
