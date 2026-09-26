import httpx

from .azure_stt import AzureStt
from .azure_tts import AzureTts
from .base import Adapter
from .crop_health import CropHealth
from .fakes import FakeMode, FakeTransport
from .gemini import Gemini
from .gemini_live import GeminiLive
from .infobip import Infobip
from .maps import Maps
from .open_meteo import OpenMeteo
from .settings import ServiceSettings
from .soilgrids import SoilGrids
from .turnstile import Turnstile
from .twilio import Twilio


class ServiceRegistry:
    def __init__(
        self,
        settings: ServiceSettings,
        *,
        fake_modes: dict[str, FakeMode] | None = None,
        max_attempts: int = 3,
    ):
        if not 1 <= max_attempts <= 3:
            raise ValueError("Attempts must be between one and three")
        self.transport = FakeTransport(fake_modes) if settings.integrations_mode == "fake" else None
        if settings.environment == "ci" and settings.integrations_mode == "live":
            raise ValueError("Live services are forbidden in CI")
        self.client = httpx.AsyncClient(
            transport=self.transport, follow_redirects=False, trust_env=False
        )
        self.twilio = Twilio("twilio", self.client, settings)
        self.turnstile = Turnstile("turnstile", self.client, settings)
        self.azure_stt = AzureStt("azure_stt", self.client, settings)
        self.azure_tts = AzureTts("azure_tts", self.client, settings)
        self.gemini = Gemini("gemini", self.client, settings)
        self.gemini_live = GeminiLive(self.client, settings)
        self.crop_health = CropHealth("crop_health", self.client, settings)
        self.soilgrids = SoilGrids("soilgrids", self.client, settings)
        self.open_meteo = OpenMeteo("open_meteo", self.client, settings)
        self.maps = Maps("maps", self.client, settings)
        self.infobip = Infobip("infobip", self.client, settings)
        self.adapters: dict[str, Adapter] = {
            service: getattr(self, service)
            for service in (
                "twilio",
                "turnstile",
                "azure_stt",
                "azure_tts",
                "gemini",
                "crop_health",
                "soilgrids",
                "open_meteo",
                "maps",
                "infobip",
            )
        }
        for adapter in self.adapters.values():
            adapter.max_attempts = max_attempts

    async def close(self) -> None:
        await self.client.aclose()
