"""Versioned, normalized outlook contract; synthetic data is never unlabelled."""

from decimal import Decimal
from typing import Annotated, Literal, get_args

from pydantic import AwareDatetime, Field, StrictInt, StringConstraints

from farmable_backend.schemas import StrictModel
from farmable_backend.weather_contract import AvailableWeather, UnavailableWeather

Crop = Literal[
    "butternut", "cabbage", "carrots", "green_beans", "onions", "potatoes", "spinach", "tomatoes"
]
CROPS = get_args(Crop)
RunId = Annotated[str, StringConstraints(pattern=r"^[a-z0-9][a-z0-9_-]{0,63}$")]
Amount = Annotated[Decimal, Field(max_digits=14, decimal_places=4, allow_inf_nan=False)]
PositiveAmount = Annotated[Amount, Field(gt=0)]
Month = Annotated[StrictInt, Field(ge=1, le=12)]
Mode = Literal["disabled", "sample", "historical", "retrospective"]
Kind = Literal["synthetic", "historical", "retrospective"]
Method = Literal["fixture", "historical_range", "lightgbm"]
SAMPLE_WARNING = "Synthetic demonstration data. Not a validated forecast or farming recommendation."
RETROSPECTIVE_WARNING = (
    "Retrospective fixed-2025-input simulation using current-vintage market history. "
    "Does not establish what information was published at the historical planting date."
)


class ForecastRow(StrictModel):
    crop: Crop
    plant_month: Month
    growing_months: Annotated[StrictInt, Field(ge=1, le=12)]
    # Prices refer to harvest after this planting month, NOT the planting-month spot price.
    p10: Amount
    p50: Amount
    p90: Amount
    method: Method
    cost_per_ha: PositiveAmount
    yield_kg_per_ha: PositiveAmount


class SourceHash(StrictModel):
    name: Annotated[str, StringConstraints(pattern=r"^[a-zA-Z0-9_.-]{1,100}$")]
    sha256: Annotated[str, StringConstraints(pattern=r"^[0-9a-f]{64}$")]


class ForecastBundle(StrictModel):
    schema_version: Literal[1]
    run_id: RunId
    data_kind: Kind
    as_of: AwareDatetime
    currency: Literal["ZAR"]
    price_basis_year: Literal[2025]
    sources: Annotated[list[SourceHash], Field(min_length=1, max_length=32)]
    assumptions: Annotated[
        list[Annotated[str, StringConstraints(min_length=1, max_length=1000)]],
        Field(min_length=1, max_length=32),
    ]
    rows: Annotated[list[ForecastRow], Field(min_length=1, max_length=96)]


class PriceRange(StrictModel):
    p10: Decimal
    p50: Decimal
    p90: Decimal
    unit: Literal["ZAR/kg"] = "ZAR/kg"


class Outlook(StrictModel):
    run_id: str
    data_kind: Kind
    warning: str | None
    forecast_as_of: AwareDatetime
    currency: Literal["ZAR"] = "ZAR"
    price_basis_year: Literal[2025] = 2025
    crop: Crop
    plant_month: int
    harvest_month: int
    price_range: PriceRange
    method: Method
    cost_per_ha: Decimal
    yield_kg_per_ha: Decimal
    break_even_price_per_kg: Decimal
    weather_risk: Annotated[AvailableWeather | UnavailableWeather, Field(discriminator="status")]
    assumptions: list[str]
