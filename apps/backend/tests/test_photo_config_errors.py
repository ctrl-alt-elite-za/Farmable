"""A deployment misconfiguration must not destroy the farmer's photos.

`create_gcs_photos` reports a bad `PHOTO_SIGNER_EMAIL` or the wrong credential
kind by raising `UploadError`, the same channel the adapters use for storage
faults and missing bucket privacy controls. These codes describe the *deployment*,
not the photo, and are fixed by an operator editing configuration — so they must
be retryable.

Classifying them as permanent loses the photo twice over: the worker marks the
upload `failed` on its first pass, and because the code is then absent from
`RECOVERABLE_ERRORS` the explicit retry endpoint refuses it. Re-reserving cannot
recover either, since `uq_photo_uploads_local` still holds the farmer's
`local_media_id`. The photo becomes unuploadable from that phone for good, and
the window in which this happens is first-time GCS setup.
"""

from datetime import UTC, datetime, timedelta

import pytest
from farmable_backend.models import Media, PhotoAttempt, PhotoUpload
from farmable_backend.photo_policy import (
    MAX_CLAIMS,
    RECOVERABLE_ERRORS,
    TRANSIENT_ERRORS,
    public_photo_error,
)
from sqlalchemy import func, select
from test_records_api import process, queue, reserve

pytest_plugins = ("test_records_api",)

# Raised by the GCS adapter's signer, credential and bucket privacy validation.
CONFIG_ERRORS = ("signer_required", "workload_credentials_required", "private_bucket_required")


@pytest.mark.parametrize("code", CONFIG_ERRORS)
def test_configuration_errors_are_transient(code):
    """The policy tables themselves, independent of any worker run."""
    assert code in TRANSIENT_ERRORS
    assert code in RECOVERABLE_ERRORS
    assert public_photo_error(code) == "temporarily_unavailable"


@pytest.mark.parametrize("code", CONFIG_ERRORS)
def test_misconfigured_deployment_requeues_rather_than_failing(records, code):
    """Given a queued photo and a misconfigured signer, when the worker runs
    once, then the upload waits for the operator instead of dying."""
    _, _, upload, _ = queue(records)
    records.storage.failure = code

    process(records, records.jobs.claim(upload.id))

    with records.sessions.begin() as session:
        row = session.get(PhotoUpload, upload.id)
        assert row.state == "queued", f"{code} permanently failed the upload"
        assert row.error_code == code


@pytest.mark.parametrize("code", CONFIG_ERRORS)
def test_photo_survives_a_whole_misconfigured_budget(records, code):
    """Even after every claim is spent, the farmer can still recover the photo
    once the operator fixes the configuration — the identity is not burned."""
    payload, _, upload, attempt = queue(records)
    records.storage.failure = code
    for _ in range(MAX_CLAIMS):
        process(records, records.jobs.claim(upload.id))
        with records.sessions.begin() as session:
            session.get(PhotoAttempt, attempt.id).next_attempt_at = datetime.now(UTC) - timedelta(
                seconds=1
            )

    path = f"/farms/{records.ids.farm}/photo-uploads/{upload.id}"
    view = records.client.get(path).json()
    assert view["error_code"] == "temporarily_unavailable"
    assert view["retryable"] is True, f"{code} left the photo unrecoverable"

    recovered = records.client.post(f"{path}/retry", json={"failed_attempt_id": view["attempt_id"]})
    assert recovered.status_code == 200
    assert recovered.json()["state"] == "awaiting_upload"
    for key in ("upload_id", "mutation_id", "entity_id", "owner_id", "farm_id"):
        assert recovered.json()[key] == view[key]
    records.storage.failure = None
    replay, _, successor = records.service.reserve(
        records.ids.authorization, records.ids.farm, payload
    )
    assert replay.attempt_id != attempt.id
    assert successor.attempt_count == 0
    records.service.upload(records.ids.authorization, records.ids.farm, upload.id, complete=True)
    process(records, records.jobs.claim(upload.id))
    ready = records.client.get(path).json()
    assert ready["state"] == "ready"
    assert ready["cloud_media_id"] == str(upload.media_id)
    with records.sessions() as session:
        assert session.scalar(select(func.count()).select_from(Media)) == 1


@pytest.mark.parametrize("code", CONFIG_ERRORS)
def test_configuration_error_never_reaches_the_client(records, code):
    """The operator's problem is not the farmer's to read."""
    _, _, upload, _ = reserve(records)
    with records.sessions.begin() as session:
        row = session.get(PhotoUpload, upload.id)
        row.state, row.error_code = "failed", code
    result = records.client.get(f"/farms/{records.ids.farm}/photo-uploads/{upload.id}")
    assert code not in result.text
