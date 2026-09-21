import re
from xml.sax.saxutils import escape

import httpx

from .base import Adapter, ServiceResult


class AzureTts(Adapter):
    async def synthesize(
        self, text: str, voice: str = "en-ZA-LukeNeural", language: str = "en-ZA"
    ) -> ServiceResult:
        if (
            not text.strip()
            or len(text) > 4000
            or not re.fullmatch(r"[a-z]{2,3}-[A-Z]{2}", language)
            or not re.fullmatch(r"[a-zA-Z0-9-]{1,80}", voice)
        ):
            return self.failure("invalid_input")
        key = self.secret(self.settings.azure_speech_key)
        region = (
            "southafricanorth"
            if self.settings.integrations_mode == "fake"
            else self.settings.azure_speech_region
        )
        if not key or not region:
            return self.failure("misconfigured")
        ssml = (
            '<speak version="1.0" xmlns="http://www.w3.org/2001/10/synthesis" '
            f'xml:lang="{language}"><voice name="{voice}">'
            f"{escape(text)}</voice></speak>"
        )
        return await self.call(
            httpx.Request(
                "POST",
                f"https://{region}.tts.speech.microsoft.com/cognitiveservices/v1",
                headers={
                    "Ocp-Apim-Subscription-Key": key,
                    "Content-Type": "application/ssml+xml",
                    "X-Microsoft-OutputFormat": "riff-16khz-16bit-mono-pcm",
                    "User-Agent": "Farmable",
                },
                content=ssml.encode(),
            ),
            binary=True,
        )
