import base64
import binascii

import httpx

from .base import Adapter, ServiceResult


class CropHealth(Adapter):
    async def identify(self, images: list[str]) -> ServiceResult:
        if not 1 <= len(images) <= 5 or any(len(image) > 6 * 1024 * 1024 for image in images):
            return self.failure("invalid_input")
        try:
            if any(not base64.b64decode(image, validate=True) for image in images):
                return self.failure("invalid_input")
        except (ValueError, binascii.Error):
            return self.failure("invalid_input")
        key = self.secret(self.settings.crop_health_api_key)
        if not key:
            return self.failure("misconfigured")
        return await self.call(
            httpx.Request(
                "POST",
                "https://crop.kindwise.com/api/v1/identification",
                headers={"Api-Key": key},
                json={"images": images, "similar_images": False},
            )
        )
