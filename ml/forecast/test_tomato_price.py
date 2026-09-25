"""The public tomato price validator rejects production fields and malformed runs."""

import json
from datetime import date
from decimal import Decimal

import pytest
from farmable_ml.data import Crop
from farmable_ml.scenario import MARKET
from farmable_ml.seven_default import SCENARIO_ID
from validate_tomato_price import validate


def test_tomato_price_validator(tmp_path):
    rows = [
        {
            "crop": Crop.TOMATOES.value,
            "market": MARKET,
            "target_month": date(2025, month, 1).isoformat(),
            "as_of": date(2025, 1, 1).isoformat(),
            "method": "historical_range",
            "p10": str(Decimal("1.1")),
            "p50": str(Decimal("2.2")),
            "p90": str(Decimal("3.3")),
            "currency": "ZAR",
            "price_basis_year": 2025,
            "unit": "ZAR/kg",
        }
        for month in range(1, 13)
    ]
    document = {
        "scenario": SCENARIO_ID,
        "run_id": "a" * 64,
        "input_hashes": {"market": "b" * 64},
        "rows": rows,
    }
    path = tmp_path / "tomato_price_forecasts.json"
    path.write_text(json.dumps(document), encoding="utf-8")
    validate(path)
    rows[0]["cost_per_ha"] = "1"
    path.write_text(json.dumps(document), encoding="utf-8")
    with pytest.raises(ValueError, match="incorrect columns"):
        validate(path)
