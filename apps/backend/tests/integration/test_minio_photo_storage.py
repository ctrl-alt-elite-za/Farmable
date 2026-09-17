"""Real MinIO boundary tests; NOT the pending HTTP/media/job acceptance flow."""

import os
from io import BytesIO
from uuid import uuid4

import boto3
import httpx
import pytest
from botocore.config import Config
from farmable_backend.uploads import PhotoSpec, PhotoStorage, PostUpload, UploadError
from PIL import Image

pytestmark = pytest.mark.integration


@pytest.fixture
def storage():
    endpoint = os.environ.get("UPLOAD_TEST_ENDPOINT")
    if not endpoint:
        pytest.skip("Requires the isolated scripts/test-upload-storage.sh MinIO stack")
    client = boto3.client(
        "s3",
        endpoint_url=endpoint,
        region_name="us-east-1",
        aws_access_key_id=os.environ["UPLOAD_TEST_USER"],
        aws_secret_access_key=os.environ["UPLOAD_TEST_PASSWORD"],
        config=Config(
            signature_version="s3v4",
            connect_timeout=3,
            read_timeout=5,
            retries={"total_max_attempts": 1},
            s3={"addressing_style": "path"},
        ),
    )
    bucket = "photos-" + uuid4().hex
    client.create_bucket(Bucket=bucket)
    yield PhotoStorage(client, bucket, local_test_without_kms=True), client, bucket
    # Never clean an external bucket: only the randomly created fixture bucket.
    for item in client.list_objects_v2(Bucket=bucket).get("Contents", []):
        client.delete_object(Bucket=bucket, Key=item["Key"])
    client.delete_bucket(Bucket=bucket)


def gps_photo():
    with Image.new("RGB", (12, 8), "red") as image, BytesIO() as stream:
        exif = Image.Exif()
        exif[0x8825] = {1: "N", 2: (1, 2, 3), 3: "E", 4: (4, 5, 6)}
        image.save(stream, format="JPEG", exif=exif)
        return stream.getvalue()


def post_file(upload, data, **fields):
    # Never print a presigned form, response body, or provider credentials.
    with httpx.Client(timeout=15, trust_env=False) as http:
        response = http.post(
            upload.url,
            data={**upload.fields, **fields},
            files={"file": ("photo.jpg", data, "image/jpeg")},
        )
        return response.status_code


def test_real_upload_sanitize_private_copy_and_replay_isolation(storage):
    store, client, bucket = storage
    data = gps_photo()
    spec = PhotoSpec(uuid4(), uuid4(), "image/jpeg", len(data))
    upload = store.prepare(spec)
    assert post_file(upload, data) == 204
    clean = store.sanitize(spec)
    with Image.open(BytesIO(clean.data)) as image:
        assert not image.getexif().get_ifd(0x8825)
    result = client.get_object(Bucket=bucket, Key=spec.clean_key)
    try:
        saved = result["Body"].read()
    finally:
        result["Body"].close()
    assert saved == clean.data
    # Anonymous clients cannot read either object; there are no public URLs.
    with httpx.Client(timeout=5, trust_env=False) as http:
        for key in (spec.incoming_key, spec.clean_key):
            assert http.get(f"{upload.url}/{key}").status_code == 403
    # A reused signed form can replace incoming, but cannot write the clean key.
    assert post_file(upload, data, key=spec.clean_key) == 403
    assert (
        post_file(
            upload, data, key=PhotoSpec(uuid4(), uuid4(), "image/jpeg", len(data)).incoming_key
        )
        == 403
    )


@pytest.mark.parametrize("mutation", ["size", "type"])
def test_storage_itself_rejects_unsigned_size_or_content_type(storage, mutation):
    store, _client, _bucket = storage
    data = gps_photo()
    spec = PhotoSpec(uuid4(), uuid4(), "image/jpeg", len(data))
    upload = store.prepare(spec)
    if mutation == "size":
        assert post_file(upload, b"x" * (20 * 1024 * 1024)) in (400, 403)
    else:
        assert post_file(upload, data, **{"Content-Type": "image/png"}) == 403


def test_storage_rejects_expired_policy_without_waiting_five_minutes(storage):
    _store, client, bucket = storage
    data = gps_photo()
    spec = PhotoSpec(uuid4(), uuid4(), "image/jpeg", len(data))
    # Same S3 POST mechanism, deliberately already expired; unit test checks 300s default.
    signed = client.generate_presigned_post(
        Bucket=bucket,
        Key=spec.incoming_key,
        ExpiresIn=-1,
        Fields={"Content-Type": "image/jpeg"},
        Conditions=[{"Content-Type": "image/jpeg"}, ["content-length-range", len(data), len(data)]],
    )
    assert post_file(PostUpload(signed["url"], signed["fields"]), data) == 403


def test_corrupt_upload_is_not_published(storage):
    store, client, bucket = storage
    data = b"this is not a JPEG"
    spec = PhotoSpec(uuid4(), uuid4(), "image/jpeg", len(data))
    assert post_file(store.prepare(spec), data) == 204
    with pytest.raises(UploadError, match="^invalid_photo$"):
        store.sanitize(spec)
    keys = [obj["Key"] for obj in client.list_objects_v2(Bucket=bucket).get("Contents", [])]
    assert spec.clean_key not in keys
