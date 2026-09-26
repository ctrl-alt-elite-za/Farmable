"""Private GCS photo operations. All calls run outside the API event loop."""

import base64
import hashlib
import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Any

import google.auth
from google.api_core import exceptions as cloud_errors
from google.api_core.retry import Retry, if_transient_error
from google.auth import credentials
from google.auth.exceptions import GoogleAuthError
from google.auth.transport.requests import AuthorizedSession, Request
from google.cloud import storage
from google.oauth2 import service_account
from requests import RequestException

from farmable_backend.record_access import utc
from farmable_backend.uploads import CleanPhoto, PostUpload, UploadError

TIMEOUT = (5, 15)


def retry_policy() -> Retry:
    failures = 0

    def retryable(error):
        nonlocal failures
        failures += 1
        return failures < 3 and if_transient_error(error)

    return Retry(predicate=retryable, initial=0.5, maximum=2, multiplier=2, timeout=45)


class BoundedRequest(Request):
    def __call__(self, *args, **kwargs):
        kwargs["timeout"] = TIMEOUT
        return super().__call__(*args, **kwargs)


class IamSigning(credentials.Signing):
    """IAM signBlob with explicit timeouts instead of the SDK signing shortcut."""

    def __init__(self, source, email: str):
        self.email = email
        self.http = AuthorizedSession(
            source, auth_request=BoundedRequest(), max_refresh_attempts=0, refresh_timeout=15
        )

    @property
    def signer_email(self):
        return self.email

    @property
    def signer(self):
        return self

    def sign_bytes(self, message):
        response = self.http.post(
            f"https://iamcredentials.googleapis.com/v1/projects/-/serviceAccounts/{self.email}:signBlob",
            json={"payload": base64.b64encode(message).decode("ascii")},
            timeout=TIMEOUT,
        )
        try:
            response.raise_for_status()
            return base64.b64decode(response.json()["signedBlob"], validate=True)
        finally:
            response.close()

    def close(self):
        self.http.close()


@dataclass(frozen=True)
class ObjectInfo:
    generation: str
    size: int
    content_type: str


def incoming_key(upload, attempt) -> str:
    return f"farms/{upload.farm_id}/media/{upload.media_id}/attempts/{attempt.id}/incoming"


def clean_key(upload, attempt) -> str:
    return f"farms/{upload.farm_id}/media/{upload.media_id}/attempts/{attempt.id}/clean"


class GcsPhotos:
    def __init__(self, client: Any, bucket: str, signing: Any):
        self.client = client
        self.bucket = client.bucket(bucket)
        self.signing = signing

    def private(self):
        try:
            self.bucket.reload(timeout=TIMEOUT, retry=retry_policy())
            iam = self.bucket.iam_configuration
            if (
                not iam.uniform_bucket_level_access_enabled
                or iam.public_access_prevention != "enforced"
            ):
                raise UploadError("private_bucket_required")
        except (cloud_errors.GoogleAPICallError, GoogleAuthError, RequestException):
            raise UploadError("private_bucket_unverified") from None

    def prepare(self, upload, attempt) -> PostUpload:
        self.private()
        try:
            result = self.client.generate_signed_post_policy_v4(
                self.bucket.name,
                incoming_key(upload, attempt),
                expiration=utc(attempt.form_expires_at),
                credentials=self.signing,
                fields={"Content-Type": upload.content_type},
                conditions=[["content-length-range", upload.byte_length, upload.byte_length]],
            )
            return PostUpload(result["url"], result["fields"])
        except (
            cloud_errors.GoogleAPICallError,
            GoogleAuthError,
            RequestException,
            ValueError,
            KeyError,
        ):
            raise UploadError("storage_unavailable") from None

    def inspect(self, upload, attempt) -> ObjectInfo:
        blob = self.bucket.blob(incoming_key(upload, attempt), generation=attempt.source_generation)
        try:
            blob.reload(timeout=TIMEOUT, retry=retry_policy())
            if blob.size != upload.byte_length:
                raise UploadError("photo_size_mismatch")
            if blob.content_type != upload.content_type or blob.content_encoding:
                raise UploadError("photo_type_mismatch")
            return ObjectInfo(str(blob.generation), blob.size, blob.content_type)
        except cloud_errors.NotFound:
            raise UploadError("incoming_missing") from None
        except (cloud_errors.GoogleAPICallError, GoogleAuthError, RequestException):
            raise UploadError("storage_unavailable") from None

    def read(self, upload, attempt) -> bytes:
        if attempt.source_generation is None:
            raise UploadError("source_not_pinned")
        blob = self.bucket.blob(incoming_key(upload, attempt), generation=attempt.source_generation)
        try:
            data = blob.download_as_bytes(
                start=0,
                end=upload.byte_length,
                raw_download=True,
                if_generation_match=int(attempt.source_generation),
                timeout=TIMEOUT,
                retry=retry_policy(),
            )
            if len(data) != upload.byte_length:
                raise UploadError("photo_size_mismatch")
            return data
        except cloud_errors.NotFound:
            raise UploadError("incoming_missing") from None
        except (cloud_errors.GoogleAPICallError, GoogleAuthError, RequestException):
            raise UploadError("storage_unavailable") from None

    def read_clean(self, upload, attempt) -> bytes:
        if (
            not attempt.clean_generation
            or not attempt.clean_sha256
            or not attempt.clean_size
            or not 0 < attempt.clean_size <= 4_500_000
        ):
            raise UploadError("clean_photo_unavailable")
        blob = self.bucket.blob(clean_key(upload, attempt), generation=attempt.clean_generation)
        try:
            data = blob.download_as_bytes(
                start=0,
                end=attempt.clean_size,
                raw_download=True,
                if_generation_match=int(attempt.clean_generation),
                timeout=TIMEOUT,
                retry=retry_policy(),
            )
            if (
                len(data) != attempt.clean_size
                or hashlib.sha256(data).hexdigest() != attempt.clean_sha256
            ):
                raise UploadError("clean_object_conflict")
            return data
        except cloud_errors.NotFound:
            raise UploadError("clean_photo_unavailable") from None
        except (cloud_errors.GoogleAPICallError, GoogleAuthError, RequestException):
            raise UploadError("storage_unavailable") from None

    def publish(self, upload, attempt, clean: CleanPhoto) -> str:
        blob = self.bucket.blob(clean_key(upload, attempt))
        digest = hashlib.sha256(clean.data).hexdigest()
        try:
            try:
                blob.upload_from_string(
                    clean.data,
                    content_type=clean.content_type,
                    if_generation_match=0,
                    timeout=TIMEOUT,
                    retry=retry_policy(),
                    checksum="crc32c",
                )
            except cloud_errors.PreconditionFailed:
                # Lost write response/DB commit: verify actual bounded bytes, not
                # just caller-writable metadata, before reusing the object.
                blob.reload(timeout=TIMEOUT, retry=retry_policy())
                if (
                    blob.size != len(clean.data)
                    or blob.content_type != clean.content_type
                    or blob.content_encoding
                ):
                    raise UploadError("clean_object_conflict") from None
                existing = blob.download_as_bytes(
                    start=0,
                    end=len(clean.data),
                    raw_download=True,
                    if_generation_match=int(blob.generation),
                    timeout=TIMEOUT,
                    retry=retry_policy(),
                )
                if hashlib.sha256(existing).hexdigest() != digest:
                    raise UploadError("clean_object_conflict") from None
            return str(blob.generation)
        except (cloud_errors.GoogleAPICallError, GoogleAuthError, RequestException):
            raise UploadError("storage_unavailable") from None

    def cleanup(
        self, upload, attempt, *, keep_clean: bool, should_stop: Callable[[], bool] = lambda: False
    ) -> bool:
        """At most 100 generations; exact-name checks protect siblings/prefixes."""
        try:
            keys = [incoming_key(upload, attempt)]
            if not keep_clean:
                keys.append(clean_key(upload, attempt))
            remaining = 100
            for key in keys:
                if should_stop():
                    return False
                blobs = self.client.list_blobs(
                    self.bucket,
                    prefix=key,
                    versions=True,
                    max_results=remaining + 1,
                    page_size=remaining + 1,
                    timeout=TIMEOUT,
                    retry=retry_policy(),
                )
                for blob in blobs:
                    if should_stop():
                        return False
                    if blob.name != key:
                        continue
                    if remaining == 0:
                        return False
                    try:
                        blob.delete(
                            if_generation_match=int(blob.generation),
                            timeout=TIMEOUT,
                            retry=retry_policy(),
                        )
                    except cloud_errors.NotFound:
                        pass
                    remaining -= 1
            return True
        except (cloud_errors.GoogleAPICallError, GoogleAuthError, RequestException):
            raise UploadError("storage_unavailable") from None

    def close(self):
        self.client.close()
        self.signing.close()


def create_gcs_photos(settings) -> GcsPhotos | None:
    if not settings.photo_bucket:
        return None
    if not re.fullmatch(
        r"[a-zA-Z0-9._-]+@[a-zA-Z0-9.-]+\.iam\.gserviceaccount\.com",
        settings.photo_signer_email or "",
    ):
        raise UploadError("signer_required")
    try:
        source, project = google.auth.default(
            scopes=["https://www.googleapis.com/auth/cloud-platform"], request=BoundedRequest()
        )
        if isinstance(source, service_account.Credentials):
            raise UploadError("workload_credentials_required")
        http = AuthorizedSession(
            source, auth_request=BoundedRequest(), max_refresh_attempts=0, refresh_timeout=15
        )
        client = storage.Client(project=project, credentials=source, _http=http)
        return GcsPhotos(
            client, settings.photo_bucket, IamSigning(source, settings.photo_signer_email)
        )
    except UploadError:
        raise
    except (GoogleAuthError, RequestException, ValueError, OSError):
        raise UploadError("storage_unavailable") from None


def create_photos(settings):
    """The configured photo storage: private GCS, or disposable CI storage."""
    if getattr(settings, "photo_test_storage_url", None):
        from farmable_backend.ci_photos import create_ci_photos

        return create_ci_photos(settings)
    return create_gcs_photos(settings)
