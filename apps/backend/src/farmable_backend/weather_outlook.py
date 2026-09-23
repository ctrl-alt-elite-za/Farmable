"""One indexed cache lookup after owner authorization; never fetch on the read path."""

from farmable_backend.models import WeatherRiskClimatology
from farmable_backend.record_access import db_now, utc
from farmable_backend.weather_contract import AvailableWeather, UnavailableWeather
from farmable_backend.weather_policy import (
    POLICY,
    POLICY_HASH,
    THRESHOLDS,
    WARNING,
    grid_cell,
    job_key,
    planting_years,
)


def cached_weather(session, boundary, crop, month, integrations_mode):
    cell = grid_cell(boundary)
    if cell is None or integrations_mode not in {"live", "fake"}:
        return UnavailableWeather()
    first, last = planting_years(db_now(session).date())
    row = session.get(WeatherRiskClimatology, (job_key(cell, first, last), crop, month))
    kind = "synthetic" if integrations_mode == "fake" else "historical"
    # Fake and live worker configurations must never contaminate one another.
    if row is None or row.payload["data_kind"] != kind:
        return UnavailableWeather()
    return AvailableWeather(
        **row.payload,
        policy_version=POLICY["version"],
        policy_sha256=POLICY_HASH,
        source="synthetic fixture" if kind == "synthetic" else "Open-Meteo ERA5",
        computed_at=utc(row.computed_at),
        first_planting_year=first,
        last_planting_year=last,
        thresholds=THRESHOLDS,
        warning=("Synthetic weather fixture. " if kind == "synthetic" else "") + WARNING,
    )
