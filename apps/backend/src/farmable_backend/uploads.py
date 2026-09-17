"""Photo-storage boundary; authentication, media records and jobs live upstream.

Only server-issued UUIDs and a persisted PhotoSpec may reach this module. Never
log a PostUpload: its form fields are bearer credentials. All SDK calls are
synchronous and belong in a worker or thread, not the async API event loop.
"""

from dataclasses import dataclass, field
from io import BytesIO
from typing import Any
from uuid import UUID

import boto3
from botocore.config import Config
from botocore.exceptions import BotoCoreError, ClientError
from PIL import Image, ImageOps, UnidentifiedImageError

MAX_PHOTO_BYTES = 5_000_000
MAX_PHOTO_PIXELS = 20_000_000
UPLOAD_EXPIRY_SECONDS = 300
_FORMATS = {"image/jpeg": "JPEG", "image/png": "PNG"}


class UploadError(ValueError):
    """A stable error code, never an SDK message or user-controlled metadata."""


@dataclass(frozen=True)
class PhotoSpec:
    farm_id: UUID
    media_id: UUID
    content_type: str
    size: int

    def __post_init__(self) -> None:
        if not isinstance(self.farm_id, UUID) or not isinstance(self.media_id, UUID):
            raise UploadError("invalid_media_identity")
        if self.content_type not in _FORMATS:
            raise UploadError("unsupported_photo_type")
        if type(self.size) is not int or not 0 < self.size <= MAX_PHOTO_BYTES:
            raise UploadError("invalid_photo_size")

    @property
    def incoming_key(self) -> str:
        return f"farms/{self.farm_id}/media/{self.media_id}/incoming"

    @property
    def clean_key(self) -> str:
        return f"farms/{self.farm_id}/media/{self.media_id}/clean"


@dataclass(frozen=True)
class PostUpload:
    url: str = field(repr=False)
    fields: dict[str, str] = field(repr=False)
    expires_in: int = UPLOAD_EXPIRY_SECONDS


@dataclass(frozen=True)
class CleanPhoto:
    data: bytes = field(repr=False)
    content_type: str
    width: int
    height: int


class _BoundedOutput(BytesIO):
    def write(self, data: Any) -> int:
        if self.tell() + len(data) > MAX_PHOTO_BYTES:
            raise UploadError("clean_photo_too_large")
        return super().write(data)


def sanitize_photo(data: bytes, content_type: str) -> CleanPhoto:
    """Decode real pixels, orient them, and re-encode without ANY metadata.

    EXIF GPS can also hide in PNG text/XMP. Removing just one EXIF tag is not
    sufficient. Copying pixels to a fresh image excludes all original metadata.
    """
    if content_type not in _FORMATS:
        raise UploadError("unsupported_photo_type")
    if not 0 < len(data) <= MAX_PHOTO_BYTES:
        raise UploadError("invalid_photo_size")
    try:
        with Image.open(BytesIO(data), formats=["JPEG", "PNG"]) as original:
            if original.format != _FORMATS[content_type]:
                raise UploadError("photo_type_mismatch")
            if original.width * original.height > MAX_PHOTO_PIXELS:
                raise UploadError("photo_dimensions_too_large")
            if getattr(original, "n_frames", 1) != 1:
                raise UploadError("animated_photo_unsupported")
            original.load()  # Header sniffing alone does not validate an image.
            oriented = ImageOps.exif_transpose(original)
            try:
                mode = "RGB"
                if content_type == "image/png" and (
                    "A" in oriented.getbands() or "transparency" in oriented.info
                ):
                    mode = "RGBA"
                with oriented.convert(mode) as pixels, Image.new(mode, oriented.size) as clean:
                    clean.paste(pixels)
                    with _BoundedOutput() as output:
                        clean.save(output, format=_FORMATS[content_type])
                        return CleanPhoto(output.getvalue(), content_type, *clean.size)
            finally:
                oriented.close()
    except UploadError:
        raise
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError, Image.DecompressionBombError):
        raise UploadError("invalid_photo") from None


class PhotoStorage:
    """Injected S3-compatible client; secure defaults, no automatic provisioning.

    Production buckets MUST have S3 Block Public Access enabled and private IAM
    policies. The caller supplies an SDK client with finite timeouts/retries.
    SSE-S3 is required by default for incoming AND clean objects. The explicit
    test-only exception exists because disposable local MinIO has no KMS.
    """

    def __init__(self, client: Any, bucket: str, *, local_test_without_kms: bool = False):
        self._client = client
        self._bucket = bucket
        self._encrypted = not local_test_without_kms

    def prepare(self, spec: PhotoSpec) -> PostUpload:
        fields = {"Content-Type": spec.content_type}
        conditions: list[Any] = [
            {"Content-Type": spec.content_type},
            ["content-length-range", spec.size, spec.size],
        ]
        if self._encrypted:
            fields["x-amz-server-side-encryption"] = "AES256"
            conditions.append({"x-amz-server-side-encryption": "AES256"})
        try:
            signed = self._client.generate_presigned_post(
                Bucket=self._bucket,
                Key=spec.incoming_key,
                Fields=fields,
                Conditions=conditions,
                ExpiresIn=UPLOAD_EXPIRY_SECONDS,
            )
        except (BotoCoreError, ClientError):
            raise UploadError("storage_unavailable") from None
        return PostUpload(signed["url"], signed["fields"])

    def sanitize(self, spec: PhotoSpec) -> CleanPhoto:
        """Validate a bounded GET snapshot; publish only the re-encoded photo.

        A link grants writes only to `incoming`, never `clean`. Upstream must
        claim completion once, persist the returned descriptor, mark media ready
        only AFTER success, and arrange abandoned/incoming-object cleanup.
        """
        try:
            obj = self._client.get_object(Bucket=self._bucket, Key=spec.incoming_key)
            body = obj["Body"]
            try:
                if obj["ContentLength"] != spec.size:
                    raise UploadError("photo_size_mismatch")
                if obj.get("ContentType") != spec.content_type:
                    raise UploadError("photo_type_mismatch")
                if self._encrypted and obj.get("ServerSideEncryption") != "AES256":
                    raise UploadError("photo_encryption_missing")
                data = body.read(spec.size + 1)
                if len(data) != spec.size:
                    raise UploadError("photo_size_mismatch")
            finally:
                body.close()
            clean = sanitize_photo(data, spec.content_type)
            encryption = {"ServerSideEncryption": "AES256"} if self._encrypted else {}
            self._client.put_object(
                Bucket=self._bucket,
                Key=spec.clean_key,
                Body=clean.data,
                ContentType=clean.content_type,
                **encryption,
            )
            return clean
        except (BotoCoreError, ClientError):
            raise UploadError("storage_unavailable") from None


def create_s3_photo_storage(bucket: str, *, region: str = "af-south-1") -> PhotoStorage:
    """Production factory: use IAM credentials, bounded SDK calls, fail private.

    No network calls are made on module import. Explicit startup configuration
    can call this factory once schema/auth and staging bucket setup are ready.
    """
    client = boto3.client(
        "s3",
        region_name=region,
        config=Config(
            signature_version="s3v4",
            connect_timeout=5,
            read_timeout=15,
            retries={"total_max_attempts": 3, "mode": "standard"},
        ),
    )
    try:
        block = client.get_public_access_block(Bucket=bucket)["PublicAccessBlockConfiguration"]
    except (BotoCoreError, ClientError):
        raise UploadError("private_bucket_unverified") from None
    if not all(
        block.get(name) is True
        for name in (
            "BlockPublicAcls",
            "IgnorePublicAcls",
            "BlockPublicPolicy",
            "RestrictPublicBuckets",
        )
    ):
        raise UploadError("private_bucket_required")
    return PhotoStorage(client, bucket)
