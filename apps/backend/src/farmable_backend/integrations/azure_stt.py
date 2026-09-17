import io
import re
import wave

import httpx

from .base import Adapter, ServiceResult


def valid_wav(audio: bytes) -> bool:
    if not audio or len(audio) > 2 * 1024 * 1024:
        return False
    try:
        with wave.open(io.BytesIO(audio), "rb") as wav:
            return (
                wav.getnchannels() == 1
                and wav.getsampwidth() == 2
                and wav.getframerate() == 16000
                and 0 < wav.getnframes() <= 60 * 16000
                and len(wav.readframes(wav.getnframes())) == wav.getnframes() * 2
            )
    except (wave.Error, EOFError):
        return False


class AzureStt(Adapter):
    async def recognize(self, audio: bytes, language: str = "en-ZA") -> ServiceResult:
        if not valid_wav(audio) or not re.fullmatch(r"[a-z]{2,3}-[A-Z]{2}", language):
            return self.failure("invalid_input")
        key = self.secret(self.settings.azure_speech_key)
        resource = (
            "fixture"
            if self.settings.integrations_mode == "fake"
            else self.settings.azure_speech_resource
        )
        if not key or not resource:
            return self.failure("misconfigured")
        return await self.call(
            httpx.Request(
                "POST",
                f"https://{resource}.cognitiveservices.azure.com/stt/speech/recognition/conversation/cognitiveservices/v1",
                params={"language": language, "format": "simple"},
                headers={
                    "Ocp-Apim-Subscription-Key": key,
                    "Accept": "application/json",
                    "Content-Type": "audio/wav; codecs=audio/pcm; samplerate=16000",
                },
                content=audio,
            )
        )
