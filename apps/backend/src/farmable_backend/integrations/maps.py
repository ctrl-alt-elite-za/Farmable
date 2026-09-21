from urllib.parse import quote

import httpx

from .base import Adapter, ServiceResult


class Maps(Adapter):
    async def geocode(self, address: str) -> ServiceResult:
        if not address.strip() or len(address) > 512:
            return self.failure("invalid_input")
        key = self.secret(self.settings.maps_server_api_key)
        if not key:
            return self.failure("misconfigured")
        # Separate server key; never use or expose the Android package/certificate-restricted key.
        return await self.call(
            httpx.Request(
                "GET",
                "https://geocode.googleapis.com/v4/geocode/address/" + quote(address, safe=""),
                headers={
                    "X-Goog-Api-Key": key,
                    "X-Goog-FieldMask": "results.location,results.formattedAddress",
                },
            )
        )
