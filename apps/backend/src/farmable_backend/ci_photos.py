"""Disposable S3-compatible photo storage for the CI stack ONLY (#11, #17).

Production uploads go to private GCS (gcs_photos.py). This adapter speaks the
same interface to a throwaway MinIO so the mobile E2E can prove the reserve →
signed POST → complete → poll contract end to end. Settings refuse it outside
ENVIRONMENT=ci or development, and it is never built without an explicit
PHOTO_TEST_STORAGE_URL.

Objects carry no versions, so an ETag stands in for a GCS generation: reads
and reuse are pinned to the exact ETag the worker recorded.
"""

import hashlib
from datetime import UTC, datetime
from typing import Any

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError

from farmable_backend.gcs_photos import ObjectInfo, clean_key, incoming_key
from farmable_backend.record_access import utc
from farmable_backend.uploads import CleanPhoto, PostUpload, UploadError

_MISSING = {"404", "NoSuchKey", "NotFound"}


def _client(endpoint: str, user: str, password: str) -> Any:
    return boto3.client(
        "s3",
        endpoint_url=endpoint,
        region_name="us-east-1",
        aws_access_key_id=user,
        aws_secret_access_key=password,
        config=Config(
            signature_version="s3v4",
            connect_timeout=5,
            read_timeout=15,
            retries={"total_max_attempts": 3, "mode": "standard"},
            s3={"addressing_style": "path"},
        ),
    )


def _code(error: ClientError) -> str:
    return str(error.response.get("Error", {}).get("Code", ""))


def _etag(value: str) -> str:
    return value.strip('"')


class CiPhotos:
    """The GcsPhotos interface over a disposable MinIO bucket."""

    def __init__(self, client: Any, signer: Any, bucket: str):
        # [signer] points at the host the phone can reach (10.0.2.2 from the
        # emulator); [client] at the storage container. A V4 POST policy does
        # not sign the host, so the form works at either address.
        self.client = client
        self.signer = signer
        self.bucket = bucket

    def private(self):
        try:
            try:
                self.client.head_bucket(Bucket=self.bucket)
            except ClientError as error:
                if _code(error) not in _MISSING | {"NoSuchBucket"}:
                    raise
                self.client.create_bucket(Bucket=self.bucket)
            try:
                self.client.get_bucket_policy(Bucket=self.bucket)
            except ClientError as error:
                if _code(error) == "NoSuchBucketPolicy":
                    return
                raise
            # Any bucket policy could grant public reads; a fresh bucket has none.
            raise UploadError("private_bucket_required")
        except (BotoCoreError, ClientError):
            raise UploadError("private_bucket_unverified") from None

    def prepare(self, upload, attempt) -> PostUpload:
        self.private()
        seconds = int((utc(attempt.form_expires_at) - datetime.now(UTC)).total_seconds())
        if seconds <= 0:
            raise UploadError("storage_unavailable")
        try:
            signed = self.signer.generate_presigned_post(
                Bucket=self.bucket,
                Key=incoming_key(upload, attempt),
                Fields={"Content-Type": upload.content_type},
                Conditions=[
                    {"Content-Type": upload.content_type},
                    ["content-length-range", upload.byte_length, upload.byte_length],
                ],
                ExpiresIn=seconds,
            )
            return PostUpload(signed["url"], signed["fields"])
        except (BotoCoreError, ClientError, KeyError):
            raise UploadError("storage_unavailable") from None

    def inspect(self, upload, attempt) -> ObjectInfo:
        try:
            head = self.client.head_object(Bucket=self.bucket, Key=incoming_key(upload, attempt))
        except ClientError as error:
            if _code(error) in _MISSING:
                raise UploadError("incoming_missing") from None
            raise UploadError("storage_unavailable") from None
        except BotoCoreError:
            raise UploadError("storage_unavailable") from None
        if head["ContentLength"] != upload.byte_length:
            raise UploadError("photo_size_mismatch")
        if head.get("ContentType") != upload.content_type or head.get("ContentEncoding"):
            raise UploadError("photo_type_mismatch")
        return ObjectInfo(_etag(head["ETag"]), head["ContentLength"], head["ContentType"])

    def _get(self, key: str, etag: str, size: int, missing: str) -> bytes:
        try:
            obj = self.client.get_object(Bucket=self.bucket, Key=key, IfMatch=f'"{etag}"')
            body = obj["Body"]
            try:
                return body.read(size + 1)
            finally:
                body.close()
        except ClientError as error:
            if _code(error) in _MISSING:
                raise UploadError(missing) from None
            if _code(error) in {"412", "PreconditionFailed"}:
                raise UploadError("clean_object_conflict") from None
            raise UploadError("storage_unavailable") from None
        except BotoCoreError:
            raise UploadError("storage_unavailable") from None

    def read(self, upload, attempt) -> bytes:
        if attempt.source_generation is None:
            raise UploadError("source_not_pinned")
        data = self._get(
            incoming_key(upload, attempt),
            attempt.source_generation,
            upload.byte_length,
            "incoming_missing",
        )
        if len(data) != upload.byte_length:
            raise UploadError("photo_size_mismatch")
        return data

    def read_clean(self, upload, attempt) -> bytes:
        if (
            not attempt.clean_generation
            or not attempt.clean_sha256
            or not attempt.clean_size
            or not 0 < attempt.clean_size <= 4_500_000
        ):
            raise UploadError("clean_photo_unavailable")
        data = self._get(
            clean_key(upload, attempt),
            attempt.clean_generation,
            attempt.clean_size,
            "clean_photo_unavailable",
        )
        if len(data) != attempt.clean_size or hashlib.sha256(data).hexdigest() != (
            attempt.clean_sha256
        ):
            raise UploadError("clean_object_conflict")
        return data

    def publish(self, upload, attempt, clean: CleanPhoto) -> str:
        key = clean_key(upload, attempt)
        digest = hashlib.sha256(clean.data).hexdigest()
        try:
            try:
                head = self.client.head_object(Bucket=self.bucket, Key=key)
            except ClientError as error:
                if _code(error) not in _MISSING:
                    raise
                put = self.client.put_object(
                    Bucket=self.bucket, Key=key, Body=clean.data, ContentType=clean.content_type
                )
                return _etag(put["ETag"])
            # A retry after a lost response: reuse only identical bytes.
            if (
                head["ContentLength"] != len(clean.data)
                or head.get("ContentType") != clean.content_type
            ):
                raise UploadError("clean_object_conflict")
            existing = self._get(key, _etag(head["ETag"]), len(clean.data), "clean_object_conflict")
            if hashlib.sha256(existing).hexdigest() != digest:
                raise UploadError("clean_object_conflict")
            return _etag(head["ETag"])
        except (BotoCoreError, ClientError):
            raise UploadError("storage_unavailable") from None

    def cleanup(self, upload, attempt, *, keep_clean: bool, should_stop=lambda: False) -> bool:
        keys = [incoming_key(upload, attempt)]
        if not keep_clean:
            keys.append(clean_key(upload, attempt))
        try:
            for key in keys:
                if should_stop():
                    return False
                self.client.delete_object(Bucket=self.bucket, Key=key)
            return True
        except (BotoCoreError, ClientError):
            raise UploadError("storage_unavailable") from None

    def close(self):
        self.client.close()
        self.signer.close()


def create_ci_photos(settings) -> CiPhotos:
    user = settings.photo_test_storage_user
    password = settings.photo_test_storage_password
    if not (settings.photo_bucket and user and password):
        raise UploadError("storage_unavailable")
    secret = password.get_secret_value()
    return CiPhotos(
        _client(settings.photo_test_storage_url, user, secret),
        _client(
            settings.photo_test_storage_public_url or settings.photo_test_storage_url, user, secret
        ),
        settings.photo_bucket,
    )
