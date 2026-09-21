import math

import httpx

from .base import Adapter, ServiceResult


def valid_coordinates(latitude: float, longitude: float) -> bool:
    return (
        math.isfinite(latitude)
        and math.isfinite(longitude)
        and -90 <= latitude <= 90
        and -180 <= longitude <= 180
    )


class SoilGrids(Adapter):
    async def properties(self, latitude: float, longitude: float) -> ServiceResult:
        if not valid_coordinates(latitude, longitude):
            return self.failure("invalid_input")
        return await self.call(
            httpx.Request(
                "GET",
                "https://rest.isric.org/soilgrids/v2.0/properties/query",
                params={
                    "lat": latitude,
                    "lon": longitude,
                    "property": "phh2o",
                    "depth": "0-5cm",
                    "value": "mean",
                },
            )
        )
