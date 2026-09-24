"""Bounded, restart-safe diagnosis consumer of the shared crop.health adapter."""

import asyncio
import base64
import logging
from concurrent.futures import ThreadPoolExecutor

from pydantic import ValidationError

from farmable_backend.diagnosis import DiagnosisStore
from farmable_backend.diagnosis_schemas import DiagnosisResult, DiagnosisSuggestion
from farmable_backend.uploads import UploadError

logger = logging.getLogger(__name__)
NAMES = {
    "tomato": {"tomato", "solanum lycopersicum"},
    "onion": {"onion", "allium cepa"},
    "potato": {"potato", "solanum tuberosum"},
}


def normalized(data, crop, *, synthetic):
    """Persist only bounded suggestions, never tokens, URLs or treatment prose."""
    try:
        if data["status"] != "COMPLETED" or data["result"]["is_plant"]["binary"] is not True:
            raise ValueError("not_plant")
        crops = data["result"]["crop"]["suggestions"]
        diseases = data["result"]["disease"]["suggestions"]
        if not isinstance(crops, list) or not crops or not isinstance(diseases, list):
            raise ValueError("invalid_response")
        found = crops[0]
        if not any(
            str(found.get(key, "")).lower() in NAMES[crop] for key in ("name", "scientific_name")
        ):
            raise ValueError("crop_mismatch")
        return DiagnosisResult(
            data_kind="synthetic" if synthetic else "provider",
            crop=DiagnosisSuggestion(name=found["name"], probability=found["probability"]),
            suggestions=[
                DiagnosisSuggestion(name=item["name"], probability=item["probability"])
                for item in diseases[:5]
            ],
        )
    except (KeyError, TypeError, AttributeError, ValidationError):
        raise ValueError("invalid_response") from None


class DiagnosisWorker:
    def __init__(self, sessions, adapter, storage_factory):
        self.jobs = DiagnosisStore(sessions)
        self.adapter = adapter
        self.storage_factory = storage_factory
        self.storage = None
        self.stop = asyncio.Event()
        # One diagnosis slot bounds resident image bytes and paid-call concurrency.
        self.executor = ThreadPoolExecutor(max_workers=1, thread_name_prefix="farmable-diagnosis")

    async def call(self, function, *args, **kwargs):
        from functools import partial

        return await asyncio.get_running_loop().run_in_executor(
            self.executor, partial(function, *args, **kwargs)
        )

    def read_photo(self, upload, attempt):
        if self.storage is None:
            self.storage = self.storage_factory()
        if self.storage is None:
            raise UploadError("storage_unavailable")
        self.storage.private()
        return self.storage.read_clean(upload, attempt)

    async def process(self, claimed):
        row, upload, attempt = claimed
        try:
            photo = await self.call(self.read_photo, upload, attempt)
        except UploadError as exc:
            code = str(exc)
            await self.call(
                self.jobs.finish,
                row.id,
                row.lease_token,
                error="photo_unavailable",
                retry=code == "storage_unavailable",
            )
            return
        if self.stop.is_set() or not await self.call(self.jobs.authorized, row.id, row.lease_token):
            await self.call(self.jobs.finish, row.id, row.lease_token, error="scope_unavailable")
            return
        # Adapter is constructed with one attempt; queue retries only a known
        # pre-call circuit refusal or a 429. Ambiguous paid POSTs are not replayed.
        try:
            async with asyncio.timeout(21):
                response = await self.adapter.identify([base64.b64encode(photo).decode("ascii")])
        except TimeoutError:
            await self.call(self.jobs.finish, row.id, row.lease_token, error="delivery_unknown")
            return
        finally:
            del photo
        if not response.ok:
            retry = response.error == "unavailable" or response.status == 429
            error = (
                "provider_unavailable"
                if retry
                else (
                    "delivery_unknown"
                    if response.error in {"timeout", "network"}
                    else "provider_rejected"
                )
            )
            await self.call(self.jobs.finish, row.id, row.lease_token, error=error, retry=retry)
            return
        try:
            result = normalized(
                response.data, row.crop, synthetic=self.adapter.settings.integrations_mode == "fake"
            )
        except ValueError as exc:
            code = str(exc)
            await self.call(
                self.jobs.finish,
                row.id,
                row.lease_token,
                error=code if code in {"not_plant", "crop_mismatch"} else "invalid_response",
            )
            return
        await self.call(self.jobs.finish, row.id, row.lease_token, result=result)

    async def run(self):
        try:
            while not self.stop.is_set():
                try:
                    for record_id in await self.call(self.jobs.candidates):
                        if self.stop.is_set():
                            break
                        claimed = await self.call(self.jobs.claim, record_id)
                        if claimed is not None:
                            await self.process(claimed)
                except Exception:
                    # Leave uncertain in-flight claims to expire; never log photos/provider text.
                    logger.error("Diagnosis processing unavailable")
                try:
                    await asyncio.wait_for(self.stop.wait(), 5)
                except TimeoutError:
                    pass
        finally:
            await asyncio.to_thread(self.executor.shutdown, wait=True, cancel_futures=True)
            if self.storage is not None:
                await asyncio.to_thread(self.storage.close)
