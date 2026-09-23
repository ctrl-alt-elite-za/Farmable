"""Versioned weather-exposure screening, independent of price/model artifacts.

These are explicit screening scenarios, not cultivar-specific damage limits.
Sources, window choices and limitations are documented in docs/weather-risk.md.
"""

import hashlib
import json
import math
from datetime import date, timedelta
from decimal import ROUND_HALF_UP, Decimal
from typing import Any

GROWING_DAYS = {
    "butternut": 170,
    "cabbage": 120,
    "carrots": 105,
    "green_beans": 85,
    "onions": 240,
    "potatoes": 150,
    "spinach": 90,
    "tomatoes": 90,
}
THRESHOLDS = {"frost_below_c": 0, "heat_at_least_c": 35, "dry_below_mm": 1, "dry_days": 7}
POLICY = {
    "version": "weather-exposure-v1",
    "growing_days": GROWING_DAYS,
    "thresholds": THRESHOLDS,
    "years": 15,
    "model": "era5",
    "timezone": "Africa/Johannesburg",
    "window": "first-of-month-inclusive-to-growing-days-exclusive",
    "period": "latest-15-complete-planting-years-with-seven-day-release-buffer",
}
POLICY_HASH = hashlib.sha256(json.dumps(POLICY, sort_keys=True).encode()).hexdigest()
WARNING = (
    "Historical weather exposure, not a forecast or probability of crop failure. "
    "Screening thresholds are not calibrated crop-damage limits; irrigation, soil, "
    "cultivar and growth-stage effects are not modelled."
)


def grid_cell(boundary: dict[str, Any] | None) -> tuple[int, int] | None:
    """Round a WGS84 point or polygon bounding-box centre to 0.1 degrees.

    Invalid/unsupported legacy boundaries remain savable, but yield no weather.
    Refuse dateline-spanning polygons rather than silently choosing the wrong cell.
    """
    if not isinstance(boundary, dict):
        return None
    coordinates = boundary.get("coordinates")
    if boundary.get("type") == "Point":
        points = [coordinates]
    elif boundary.get("type") == "Polygon":
        if not isinstance(coordinates, list) or not coordinates:
            return None
        points = coordinates[0]
        if not isinstance(points, list) or not 4 <= len(points) <= 10000:
            return None
        if points[0] != points[-1]:
            return None
    else:
        return None
    for point in points:
        if not isinstance(point, list | tuple) or len(point) != 2:
            return None
        # Check bounds before converting huge JSON integers through math.isfinite.
        if any(type(v) not in (int, float) for v in point):
            return None
        if not -180 <= point[0] <= 180 or not -90 <= point[1] <= 90:
            return None
    longitudes, latitudes = zip(*points, strict=True)
    if max(longitudes) - min(longitudes) > 180:
        return None

    def rounded(values):
        centre = (Decimal(str(min(values))) + Decimal(str(max(values)))) / 2
        return int((centre * 10).quantize(Decimal(1), rounding=ROUND_HALF_UP))

    lat, lon = rounded(latitudes), rounded(longitudes)
    return lat, -1800 if lon == 1800 else lon


def planting_years(today: date) -> tuple[int, int]:
    # The latest December crop must have finished, including a release buffer
    # beyond the provider's five-day ERA5 delay. Never use partial final seasons.
    last = today.year - 1
    final_day = date(last, 12, 1) + timedelta(days=max(GROWING_DAYS.values()) - 1)
    if final_day > today - timedelta(days=7):
        last -= 1
    return last - 14, last


def request_period(first_year: int, last_year: int) -> tuple[date, date]:
    return date(first_year, 1, 1), date(last_year, 12, 1) + timedelta(
        days=max(GROWING_DAYS.values()) - 1
    )


def job_key(cell: tuple[int, int], first_year: int, last_year: int) -> str:
    value = f"{cell[0]}:{cell[1]}:{first_year}:{last_year}:{POLICY_HASH}"
    return hashlib.sha256(value.encode()).hexdigest()


def parse_daily(payload: dict[str, Any], start: date, end: date):
    """Reject incomplete, nonfinite or mis-unit data; missing is never zero risk."""
    fields = ("temperature_2m_min", "temperature_2m_max", "precipitation_sum")
    units = payload.get("daily_units", {})
    if any(units.get(key) != unit for key, unit in zip(fields, ("°C", "°C", "mm"), strict=True)):
        raise ValueError("weather_units")
    daily = payload.get("daily")
    count = (end - start).days + 1
    if not isinstance(daily, dict) or any(
        not isinstance(daily.get(key), list) or len(daily[key]) != count
        for key in ("time", *fields)
    ):
        raise ValueError("weather_coverage")
    result = {}
    for offset in range(count):
        day = start + timedelta(days=offset)
        if daily["time"][offset] != day.isoformat():
            raise ValueError("weather_dates")
        low, high, rain = (daily[key][offset] for key in fields)
        if any(type(v) not in (int, float) or not math.isfinite(v) for v in (low, high, rain)):
            raise ValueError("weather_missing_values")
        if not -100 <= low <= high <= 70 or not 0 <= rain <= 3000:
            raise ValueError("weather_values")
        result[day] = (low, high, rain)
    return result


def calculate(daily, first_year: int, last_year: int) -> dict[tuple[str, int], dict]:
    if last_year - first_year != 14:
        raise ValueError("weather_requires_15_years")
    result = {}
    for crop, duration in GROWING_DAYS.items():
        for month in range(1, 13):
            counts = {"frost": 0, "heat_stress": 0, "dry_spell": 0}
            for year in range(first_year, last_year + 1):
                start = date(year, month, 1)
                frost = heat = dry = False
                dry_run = 0
                for offset in range(duration):
                    values = daily.get(start + timedelta(days=offset))
                    if values is None:
                        raise ValueError("weather_coverage")
                    low, high, rain = values
                    frost |= low < THRESHOLDS["frost_below_c"]
                    heat |= high >= THRESHOLDS["heat_at_least_c"]
                    dry_run = dry_run + 1 if rain < THRESHOLDS["dry_below_mm"] else 0
                    dry |= dry_run >= THRESHOLDS["dry_days"]
                for name, occurred in zip(counts, (frost, heat, dry), strict=True):
                    counts[name] += int(occurred)
            result[crop, month] = {
                "growing_days": duration,
                "years_observed": 15,
                "event_years": counts,
                "shares": {name: count / 15 for name, count in counts.items()},
                "reasons": [name for name, count in counts.items() if count],
            }
    return result
