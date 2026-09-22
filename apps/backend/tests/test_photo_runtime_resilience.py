"""Slow storage must not consume record capacity or delay an entire cleanup batch."""

import asyncio
import threading
from concurrent.futures import ThreadPoolExecutor
from types import SimpleNamespace
from unittest.mock import Mock
from uuid import uuid4

import pytest
from farmable_backend.photo_worker import PhotoWorker
from farmable_backend.record_access import ApiError
from farmable_backend.records_api import RecordRuntime
from farmable_backend.uploads import UploadError
from test_records_api import observation_payload, upload_payload

pytest_plugins = ("test_records_api",)


def test_slow_signed_forms_leave_record_http_routes_available(records, monkeypatch):
    first, second, release = threading.Event(), threading.Event(), threading.Event()
    original = records.storage.prepare

    def blocked(*args):
        (second if first.is_set() else first).set()
        assert release.wait(10)
        return original(*args)

    monkeypatch.setattr(records.storage, "prepare", blocked)
    path = f"/farms/{records.ids.farm}/photo-uploads"
    # Start each request after the previous one commits its SQLite transaction;
    # both then remain blocked in real admitted executor threads, outside the DB.
    with ThreadPoolExecutor(max_workers=2) as callers:
        try:
            a = callers.submit(records.client.post, path, json=upload_payload(records))
            assert first.wait(5)
            b = callers.submit(records.client.post, path, json=upload_payload(records))
            assert second.wait(5)
            overloaded = records.client.post(path, json=upload_payload(records))
            assert overloaded.status_code == 503
            assert overloaded.json()["error"]["code"] == "capacity_unavailable"
            assert records.client.get("/farms").status_code == 200
            assert records.client.get(f"/farms/{records.ids.farm}/sections").status_code == 200
            created = records.client.post(
                f"/farms/{records.ids.farm}/observations", json=observation_payload(records.ids)
            )
            assert created.status_code == 200
        finally:
            release.set()
        assert a.result(timeout=5).status_code == 200
        assert b.result(timeout=5).status_code == 200


def test_cancelled_photo_request_keeps_its_slot_until_the_thread_finishes():
    runtime = RecordRuntime(Mock(), Mock())
    entered, release = threading.Event(), threading.Event()

    def held():
        entered.set()
        assert release.wait(10)

    async def exercise():
        first = asyncio.create_task(runtime.call_photo(held))
        assert await asyncio.to_thread(entered.wait, 5)
        first.cancel()
        with pytest.raises(asyncio.CancelledError):
            await first
        second = asyncio.create_task(runtime.call_photo(held))
        try:
            await asyncio.sleep(0)
            with pytest.raises(ApiError) as rejected:
                await runtime.call_photo(lambda: None)
            assert rejected.value.code == "capacity_unavailable"
            assert await runtime.call(lambda: "record capacity") == "record capacity"
        finally:
            release.set()
            await second

    try:
        asyncio.run(exercise())
    finally:
        release.set()
        runtime.close()


def test_pending_bootstrap_does_not_hold_the_lock_or_repeat_discovery():
    entered, release = threading.Event(), threading.Event()
    storage = Mock()

    def blocked():
        entered.set()
        assert release.wait(10)
        return storage

    factory = Mock(side_effect=blocked)
    runtime = RecordRuntime(Mock(), factory)
    try:
        with ThreadPoolExecutor(max_workers=2) as callers:
            try:
                first = callers.submit(runtime.get_storage)
                assert entered.wait(5)
                assert runtime.storage_lock.acquire(blocking=False)
                runtime.storage_lock.release()
                second = callers.submit(runtime.get_storage)
                with pytest.raises(ApiError) as rejected:
                    second.result(timeout=2)
                assert rejected.value.code == "dependency_unavailable"
                assert rejected.value.retry_after == 1
                factory.assert_called_once()
            finally:
                release.set()
            assert first.result(timeout=5) is storage
        assert runtime.get_storage() is storage
        factory.assert_called_once()
    finally:
        release.set()
        runtime.close()
    storage.close.assert_called_once()


@pytest.mark.parametrize("failure", [UploadError("signer_required"), RuntimeError("private-path")])
def test_failed_bootstrap_has_cooldown_and_recovers_without_leaking_details(monkeypatch, failure):
    now = [100.0]
    monkeypatch.setattr("farmable_backend.records_api.time.monotonic", lambda: now[0])
    storage = Mock()
    factory = Mock(side_effect=[failure, storage])
    runtime = RecordRuntime(Mock(), factory)
    try:
        for _ in range(3):
            with pytest.raises(ApiError) as unavailable:
                runtime.get_storage()
            assert unavailable.value.code == "dependency_unavailable"
            assert unavailable.value.retry_after == 30
            assert "private" not in str(unavailable.value)
        factory.assert_called_once()
        now[0] = 130.0
        assert runtime.get_storage() is storage
        assert factory.call_count == 2
        assert runtime.get_storage() is storage
    finally:
        runtime.close()
    storage.close.assert_called_once()


def test_disabled_storage_is_cached_until_runtime_restart():
    factory = Mock(return_value=None)
    runtime = RecordRuntime(Mock(), factory)
    try:
        for _ in range(3):
            with pytest.raises(ApiError) as disabled:
                runtime.get_storage()
            assert disabled.value.code == "photo_storage_disabled"
        factory.assert_called_once()
    finally:
        runtime.close()


def test_shutdown_during_cleanup_finishes_current_attempt_but_does_not_claim_next():
    worker = PhotoWorker(Mock(), Mock())
    storage = Mock()
    worker.storage = storage
    jobs = Mock()
    worker.jobs = jobs
    jobs.cleanup_candidates.return_value = [(1, 10), (2, 20)]
    fence = uuid4()
    jobs.cleanup_claim.return_value = (
        SimpleNamespace(id=1),
        SimpleNamespace(id=10, cleanup_token=fence),
        True,
    )

    def cleanup(*args, should_stop, **kwargs):
        worker.stop.set()
        assert should_stop()
        return False

    storage.cleanup.side_effect = cleanup
    try:
        worker.clean_batch()
        jobs.cleanup_claim.assert_called_once_with(1, 10)
        jobs.cleanup_finish.assert_called_once_with(1, 10, fence, False)
        jobs.reset_mock()
        worker.clean_batch()
        jobs.cleanup_candidates.assert_not_called()
    finally:
        worker.executor.shutdown()


@pytest.mark.parametrize("phase", ["claim", "bootstrap"])
def test_shutdown_before_cleanup_io_releases_lease_without_starting_cloud_work(phase):
    worker = PhotoWorker(Mock(), Mock())
    storage, jobs = Mock(), Mock()
    worker.jobs = jobs
    jobs.cleanup_candidates.return_value = [(1, 10), (2, 20)]
    fence = uuid4()
    claimed = (SimpleNamespace(id=1), SimpleNamespace(id=10, cleanup_token=fence), False)

    def claim(*args):
        if phase == "claim":
            worker.stop.set()
        return claimed

    def bootstrap():
        worker.stop.set()
        return storage

    jobs.cleanup_claim.side_effect = claim
    worker.storage_factory = Mock(side_effect=bootstrap)
    try:
        worker.clean_batch()
        storage.private.assert_not_called()
        storage.cleanup.assert_not_called()
        jobs.cleanup_finish.assert_called_once_with(1, 10, fence, False)
        assert jobs.cleanup_claim.call_count == 1
    finally:
        worker.executor.shutdown()
