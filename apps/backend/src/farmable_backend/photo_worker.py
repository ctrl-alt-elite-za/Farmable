"""Two processing slots and one bounded janitor in the existing worker process."""

import asyncio
import hashlib
import logging
import threading
from concurrent.futures import ThreadPoolExecutor

from farmable_backend.photo_jobs import PhotoJobs
from farmable_backend.photo_policy import TRANSIENT_ERRORS
from farmable_backend.record_access import ApiError
from farmable_backend.uploads import UploadError, sanitize_photo

logger = logging.getLogger(__name__)


class PhotoWorker:
    def __init__(self, sessions, storage_factory):
        self.jobs = PhotoJobs(sessions)
        self.storage_factory = storage_factory
        self.storage = None
        self.storage_lock = threading.Lock()
        self.executor = ThreadPoolExecutor(max_workers=3, thread_name_prefix="farmable-photo")
        self.stop = asyncio.Event()

    def get_storage(self):
        with self.storage_lock:
            if self.storage is None:
                self.storage = self.storage_factory()
            if self.storage is None:
                raise UploadError("storage_unavailable")
            return self.storage

    def process(self, upload, attempt):
        token = attempt.lease_token
        try:
            storage = self.get_storage()
            storage.private()
            info = storage.inspect(upload, attempt)
            upload, attempt = self.jobs.pin(upload.id, token, info.generation)
            data = storage.read(upload, attempt)
            clean = sanitize_photo(data, upload.content_type)
            self.jobs.descriptor(
                upload.id,
                token,
                hashlib.sha256(clean.data).hexdigest(),
                len(clean.data),
                clean.width,
                clean.height,
            )
            generation = storage.publish(upload, attempt, clean)
            self.jobs.finish(upload.id, token, generation)
        except UploadError as error:
            code = str(error)
            # UploadError originates only in our adapters/sanitizer, never SDK text.
            self.jobs.fail(upload.id, token, code, transient=code in TRANSIENT_ERRORS)
        except ApiError:
            # A stale lease must not mutate its successor. Other internal
            # consistency failures consume the claim budget after lease expiry.
            logger.warning("Photo processing claim no longer applicable")
        except Exception:
            # Leave the durable claim to expire/recover; no exception text/PII.
            logger.error("Photo processing interrupted")

    async def call(self, fn, *args):
        return await asyncio.get_running_loop().run_in_executor(self.executor, fn, *args)

    async def pause(self, seconds):
        try:
            await asyncio.wait_for(self.stop.wait(), timeout=seconds)
        except TimeoutError:
            pass

    async def slot(self):
        while not self.stop.is_set():
            try:
                for upload_id in await self.call(self.jobs.candidates):
                    if self.stop.is_set():
                        break
                    claimed = await self.call(self.jobs.claim, upload_id)
                    if claimed is None:
                        continue
                    upload, attempt = claimed
                    processing = asyncio.create_task(self.call(self.process, upload, attempt))
                    while not processing.done():
                        done, _ = await asyncio.wait({processing}, timeout=30)
                        if not done:
                            # A small separate thread-pool call keeps renewal
                            # independent from the two processing slots/janitor.
                            try:
                                await asyncio.to_thread(
                                    self.jobs.renew, upload.id, attempt.lease_token
                                )
                            except Exception:
                                # Do not free this slot while its processing
                                # thread still owns memory/cloud operations.
                                logger.error("Photo lease renewal unavailable")
                    await processing
            except Exception:
                logger.error("Photo worker scan unavailable")
            await self.pause(5)

    def clean_batch(self):
        for upload_id, attempt_id in self.jobs.cleanup_candidates():
            claimed = self.jobs.cleanup_claim(upload_id, attempt_id)
            if claimed is None:
                continue
            upload, attempt, keep_clean = claimed
            try:
                storage = self.get_storage()
                storage.private()
                done = storage.cleanup(upload, attempt, keep_clean=keep_clean)
                self.jobs.cleanup_finish(upload.id, attempt.id, attempt.cleanup_token, done)
            except Exception:
                logger.error("Photo cleanup deferred")

    async def janitor(self):
        while not self.stop.is_set():
            try:
                await self.call(self.clean_batch)
            except Exception:
                logger.error("Photo cleanup scan unavailable")
            await self.pause(60)

    async def run(self):
        try:
            await asyncio.gather(self.slot(), self.slot(), self.janitor())
        finally:
            await asyncio.to_thread(self.executor.shutdown, wait=True, cancel_futures=True)
            if self.storage is not None:
                await asyncio.to_thread(self.storage.close)
