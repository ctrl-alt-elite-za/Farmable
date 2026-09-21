"""GCS SDK contract tests; these do not prove live IAM or policy enforcement."""

import base64
import json
import logging
from datetime import UTC, datetime, timedelta
from types import SimpleNamespace
from unittest.mock import Mock
from uuid import uuid4

import pytest
from farmable_backend.gcs_photos import (
    GcsPhotos,
    IamSigning,
    clean_key,
    create_gcs_photos,
    incoming_key,
    retry_policy,
)
from farmable_backend.logging import JsonFormatter
from farmable_backend.uploads import CleanPhoto, UploadError
from google.api_core.exceptions import NotFound, PreconditionFailed
from google.auth import credentials
from google.auth.exceptions import DefaultCredentialsError
from google.cloud import storage
from google.oauth2 import service_account


class Signing(credentials.AnonymousCredentials, credentials.Signing):
    signer_email = "unit@example.iam.gserviceaccount.com"
    signer = None

    def sign_bytes(self, value):
        return b"test-signature-not-valid-outside-tests"


@pytest.fixture
def gcs():
    client = Mock()
    bucket = client.bucket.return_value
    bucket.name = "private-unit-bucket"
    bucket.iam_configuration.uniform_bucket_level_access_enabled = True
    bucket.iam_configuration.public_access_prevention = "enforced"
    upload = SimpleNamespace(
        farm_id=uuid4(), media_id=uuid4(), byte_length=10, content_type="image/png"
    )
    attempt = SimpleNamespace(
        id=uuid4(), form_expires_at=datetime.now(UTC) + timedelta(minutes=5), source_generation=None
    )
    return SimpleNamespace(
        client=client,
        bucket=bucket,
        adapter=GcsPhotos(client, bucket.name, Signing()),
        upload=upload,
        attempt=attempt,
    )


def test_signed_post_contains_exact_constraints_and_no_clean_permission(gcs):
    # Exercise the real SDK policy generator without networking/signing authority.
    real = storage.Client(project="unit", credentials=Signing())
    gcs.client.generate_signed_post_policy_v4.side_effect = real.generate_signed_post_policy_v4
    result = gcs.adapter.prepare(gcs.upload, gcs.attempt)
    policy = json.loads(base64.b64decode(result.fields["policy"]))
    conditions = policy["conditions"]
    assert {"bucket": gcs.bucket.name} in conditions
    assert {"key": incoming_key(gcs.upload, gcs.attempt)} in conditions
    assert {"Content-Type": "image/png"} in conditions
    assert ["content-length-range", 10, 10] in conditions
    assert clean_key(gcs.upload, gcs.attempt) not in json.dumps(policy)
    assert (
        datetime.fromisoformat(policy["expiration"]).timestamp()
        <= gcs.attempt.form_expires_at.timestamp() + 1
    )
    assert "test-signature" not in repr(result)
    real.close()


@pytest.mark.parametrize(
    "field,value",
    [("uniform_bucket_level_access_enabled", False), ("public_access_prevention", "inherited")],
)
def test_bucket_privacy_fails_closed(gcs, field, value):
    setattr(gcs.bucket.iam_configuration, field, value)
    with pytest.raises(UploadError, match="private_bucket_required"):
        gcs.adapter.prepare(gcs.upload, gcs.attempt)
    gcs.client.generate_signed_post_policy_v4.assert_not_called()


@pytest.mark.parametrize(
    "field,value,code",
    [
        ("size", 11, "photo_size_mismatch"),
        ("content_type", "image/jpeg", "photo_type_mismatch"),
        ("content_encoding", "gzip", "photo_type_mismatch"),
    ],
)
def test_incoming_metadata_is_rechecked(gcs, field, value, code):
    blob = gcs.bucket.blob.return_value
    blob.size, blob.content_type, blob.content_encoding, blob.generation = 10, "image/png", None, 1
    setattr(blob, field, value)
    with pytest.raises(UploadError, match=code):
        gcs.adapter.inspect(gcs.upload, gcs.attempt)


def test_reads_are_generation_pinned_raw_and_bounded(gcs):
    gcs.attempt.source_generation = "99"
    gcs.bucket.blob.return_value.download_as_bytes.return_value = b"x" * 10
    assert gcs.adapter.read(gcs.upload, gcs.attempt) == b"x" * 10
    gcs.bucket.blob.assert_called_with(incoming_key(gcs.upload, gcs.attempt), generation="99")
    args = gcs.bucket.blob.return_value.download_as_bytes.call_args.kwargs
    assert args["if_generation_match"] == 99 and args["end"] == 10 and args["raw_download"] is True
    assert args["timeout"] == (5, 15)


def test_lost_publish_reply_validates_existing_bytes_before_reuse(gcs):
    blob = gcs.bucket.blob.return_value
    blob.upload_from_string.side_effect = PreconditionFailed("synthetic")
    blob.size, blob.content_type, blob.content_encoding, blob.generation = 3, "image/png", None, 8
    blob.download_as_bytes.return_value = b"abc"
    clean = CleanPhoto(b"abc", "image/png", 1, 1)
    assert gcs.adapter.publish(gcs.upload, gcs.attempt, clean) == "8"
    assert blob.upload_from_string.call_args.kwargs["if_generation_match"] == 0
    blob.download_as_bytes.return_value = b"xyz"
    with pytest.raises(UploadError, match="clean_object_conflict"):
        gcs.adapter.publish(gcs.upload, gcs.attempt, clean)


def test_cleanup_is_exact_generation_scoped_and_keeps_ready_clean(gcs):
    incoming = Mock(name="incoming")
    incoming.name = incoming_key(gcs.upload, gcs.attempt)
    incoming.generation = 8
    sibling = Mock(name="sibling")
    sibling.name = incoming.name + "-other"
    gcs.client.list_blobs.return_value = [incoming, sibling]
    assert gcs.adapter.cleanup(gcs.upload, gcs.attempt, keep_clean=True)
    assert gcs.client.list_blobs.call_count == 1
    assert incoming.delete.call_args.kwargs["if_generation_match"] == 8
    sibling.delete.assert_not_called()


def test_cleanup_pages_are_bounded(gcs):
    objects = []
    for generation in range(101):
        blob = Mock()
        blob.name = incoming_key(gcs.upload, gcs.attempt)
        blob.generation = generation
        objects.append(blob)
    gcs.client.list_blobs.return_value = objects
    assert not gcs.adapter.cleanup(gcs.upload, gcs.attempt, keep_clean=True)
    assert sum(blob.delete.call_count for blob in objects) == 100


def test_missing_input_is_retryable_not_raw_sdk_error(gcs):
    gcs.bucket.blob.return_value.reload.side_effect = NotFound("sensitive-provider-detail")
    with pytest.raises(UploadError, match="^incoming_missing$"):
        gcs.adapter.inspect(gcs.upload, gcs.attempt)


def test_sdk_retry_policy_allows_at_most_three_attempts():
    from google.api_core.exceptions import ServiceUnavailable

    attempts = 0

    def fails():
        nonlocal attempts
        attempts += 1
        raise ServiceUnavailable("synthetic")

    with pytest.raises(ServiceUnavailable):
        retry_policy()(fails)()
    assert attempts == 3


def test_disabled_storage_does_not_resolve_credentials(monkeypatch):
    lookup = Mock(side_effect=AssertionError("Must not request credentials"))
    monkeypatch.setattr("farmable_backend.gcs_photos.google.auth.default", lookup)
    assert create_gcs_photos(SimpleNamespace(photo_bucket=None)) is None
    lookup.assert_not_called()


def test_missing_signer_fails_before_resolving_credentials(monkeypatch):
    lookup = Mock(side_effect=AssertionError("Must not request credentials"))
    monkeypatch.setattr("farmable_backend.gcs_photos.google.auth.default", lookup)
    with pytest.raises(UploadError, match="^signer_required$"):
        create_gcs_photos(SimpleNamespace(photo_bucket="private-unit", photo_signer_email=None))
    lookup.assert_not_called()


def test_missing_workload_credentials_are_sanitized(monkeypatch):
    monkeypatch.setattr(
        "farmable_backend.gcs_photos.google.auth.default",
        Mock(side_effect=DefaultCredentialsError("sensitive-credential-path")),
    )
    with pytest.raises(UploadError, match="^storage_unavailable$"):
        create_gcs_photos(
            SimpleNamespace(photo_bucket="private-unit", photo_signer_email=Signing.signer_email)
        )


def test_private_key_credentials_are_rejected(monkeypatch):
    monkeypatch.setattr(
        "farmable_backend.gcs_photos.google.auth.default",
        Mock(return_value=(Mock(spec=service_account.Credentials), "unit")),
    )
    with pytest.raises(UploadError, match="^workload_credentials_required$"):
        create_gcs_photos(
            SimpleNamespace(photo_bucket="private-unit", photo_signer_email=Signing.signer_email)
        )


def test_iam_signing_uses_bounded_transport_and_closes_response(monkeypatch):
    transport = Mock()
    factory = Mock(return_value=transport)
    monkeypatch.setattr("farmable_backend.gcs_photos.AuthorizedSession", factory)
    response = transport.post.return_value
    response.json.return_value = {"signedBlob": base64.b64encode(b"signature").decode()}
    signer = IamSigning(credentials.AnonymousCredentials(), Signing.signer_email)
    try:
        assert signer.sign_bytes(b"policy") == b"signature"
        assert factory.call_args.kwargs["max_refresh_attempts"] == 0
        assert factory.call_args.kwargs["refresh_timeout"] == 15
        assert transport.post.call_args.kwargs["timeout"] == (5, 15)
        assert transport.post.call_args.kwargs["json"] == {"payload": "cG9saWN5"}
        response.close.assert_called_once()
        response.reset_mock()
        response.json.return_value = {"signedBlob": "not-valid-base64!"}
        with pytest.raises(ValueError):
            signer.sign_bytes(b"policy")
        response.close.assert_called_once()
    finally:
        signer.close()
    transport.close.assert_called_once()


@pytest.mark.parametrize(
    "name",
    [
        "google.auth.transport",
        "google.cloud.storage",
        "google.api_core.retry",
        "urllib3.connectionpool",
    ],
)
def test_cloud_wire_messages_are_opaque_even_at_debug(name):
    record = logging.LogRecord(
        name,
        logging.DEBUG,
        "",
        1,
        "https://private.invalid/object?signature=short-secret image=private-bytes",
        (),
        None,
    )
    data = json.loads(JsonFormatter().format(record))
    assert data["message"] == "Storage transport event"
    assert "private" not in data["message"]
