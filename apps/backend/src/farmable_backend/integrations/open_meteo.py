from datetime import date

import httpx

from farmable_backend.weather_policy import parse_daily

from .base import Adapter, ProviderFailure, ServiceResult
from .soilgrids import valid_coordinates


class OpenMeteo(Adapter):
    async def response(self, request: httpx.Request, binary: bool) -> ServiceResult:
        result = await super().response(request, binary)
        if request.url.path == "/v1/archive":
            try:
                parse_daily(
                    result.data or {},
                    date.fromisoformat(request.url.params["start_date"]),
                    date.fromisoformat(request.url.params["end_date"]),
                )
            except (ValueError, TypeError, AttributeError, OverflowError):
                # Validate before Adapter records success, so malformed history
                # also counts toward the per-provider circuit breaker.
                raise ProviderFailure("invalid_response") from None
        return result

    async def history(
        self, latitude_tenths: int, longitude_tenths: int, start: date, end: date
    ) -> ServiceResult:
        # Accept integer grid coordinates only: exact section coordinates cannot
        # accidentally leak through this method, even from a future caller.
        if (
            type(latitude_tenths) is not int
            or type(longitude_tenths) is not int
            or not -900 <= latitude_tenths <= 900
            or not -1800 <= longitude_tenths <= 1799
            or not 0 <= (end - start).days <= 6200
        ):
            return self.failure("invalid_input")
        return await self.call(
            httpx.Request(
                "GET",
                "https://archive-api.open-meteo.com/v1/archive",
                params={
                    "latitude": latitude_tenths / 10,
                    "longitude": longitude_tenths / 10,
                    "start_date": start.isoformat(),
                    "end_date": end.isoformat(),
                    "daily": "temperature_2m_min,temperature_2m_max,precipitation_sum",
                    "temperature_unit": "celsius",
                    "precipitation_unit": "mm",
                    "timezone": "Africa/Johannesburg",
                    "models": "era5",
                },
            )
        )

    async def forecast(self, latitude: float, longitude: float) -> ServiceResult:
        if not valid_coordinates(latitude, longitude):
            return self.failure("invalid_input")
        return await self.call(
            httpx.Request(
                "GET",
                "https://api.open-meteo.com/v1/forecast",
                params={
                    "latitude": latitude,
                    "longitude": longitude,
                    "daily": "temperature_2m_max,precipitation_sum",
                    "timezone": "UTC",
                    "forecast_days": 1,
                },
            )
        )
