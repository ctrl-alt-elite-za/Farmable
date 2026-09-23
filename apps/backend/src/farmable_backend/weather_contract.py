"""Historical exposure is distinct from current forecasts and crop-loss probability."""

from datetime import datetime
from typing import Annotated, Literal

from pydantic import Field

from farmable_backend.schemas import StrictModel

Risk = Literal["frost", "heat_stress", "dry_spell"]
Share = Annotated[float, Field(ge=0, le=1, allow_inf_nan=False)]
Count = Annotated[int, Field(ge=0, le=15)]


class UnavailableWeather(StrictModel):
    status: Literal["unavailable"] = "unavailable"
    reasons: list[Literal["climatology_not_computed"]] = ["climatology_not_computed"]


class WeatherShares(StrictModel):
    frost: Share
    heat_stress: Share
    dry_spell: Share


class WeatherEventYears(StrictModel):
    frost: Count
    heat_stress: Count
    dry_spell: Count


class AvailableWeather(StrictModel):
    status: Literal["available"] = "available"
    data_kind: Literal["historical", "synthetic"]
    basis: Literal["historical_weather_exposure"] = "historical_weather_exposure"
    policy_version: str
    policy_sha256: str
    source: Literal["Open-Meteo ERA5", "synthetic fixture"]
    source_sha256: str
    computed_at: datetime
    first_planting_year: int
    last_planting_year: int
    years_observed: Literal[15] = 15
    growing_days: int
    event_years: WeatherEventYears
    shares: WeatherShares
    reasons: list[Risk]
    thresholds: dict[str, int]
    warning: str
