import httpx

from .base import Adapter, ServiceResult
from .soilgrids import valid_coordinates


class OpenMeteo(Adapter):
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
