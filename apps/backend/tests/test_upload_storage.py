import base64
import json
from datetime import UTC, datetime
from io import BytesIO
from unittest.mock import Mock, patch
from uuid import uuid4

import boto3
import pytest
from botocore.config import Config
from botocore.exceptions import ClientError
from farmable_backend.uploads import (
    MAX_PHOTO_BYTES,
    PhotoSpec,
    PhotoStorage,
    UploadError,
    create_s3_photo_storage,
    sanitize_photo,
)
from PIL import Image, PngImagePlugin


def photo_bytes(kind="JPEG", *, gps=False, orientation=None, mode="RGB"):
    with Image.new(mode, (12, 8), "red") as photo, BytesIO() as stream:
        exif = Image.Exif()
        if gps:
            exif[0x8825] = {1: "N", 2: (1, 2, 3), 3: "E", 4: (4, 5, 6)}
        if orientation:
            exif[0x0112] = orientation
        info = PngImagePlugin.PngInfo()
        info.add_text("XML:com.adobe.xmp", "GPSLatitude=1; GPSLongitude=4")
        photo.save(stream, format=kind, exif=exif, pnginfo=info)
        return stream.getvalue()


@pytest.mark.parametrize("kind,content_type", [("JPEG", "image/jpeg"), ("PNG", "image/png")])
def test_exif_gps_and_other_metadata_removed(kind, content_type):
    data = photo_bytes(kind, gps=True)
    with Image.open(BytesIO(data)) as original:
        assert original.getexif().get_ifd(0x8825)  # The fixture really has GPS.
    clean = sanitize_photo(data, content_type)
    with Image.open(BytesIO(clean.data)) as result:
        result.load()
        assert not result.getexif()
        assert not result.getexif().get_ifd(0x8825)
        assert "XML:com.adobe.xmp" not in result.info
        assert result.format == kind
        assert result.size == (12, 8)
    assert clean.content_type == content_type
    assert "GPS" not in repr(clean)


def test_orientation_is_applied_before_metadata_removal():
    clean = sanitize_photo(photo_bytes(orientation=6), "image/jpeg")
    assert (clean.width, clean.height) == (8, 12)
    with Image.open(BytesIO(clean.data)) as result:
        assert result.size == (8, 12)
        assert not result.getexif()


def test_png_transparency_preserved():
    clean = sanitize_photo(photo_bytes("PNG", mode="RGBA"), "image/png")
    with Image.open(BytesIO(clean.data)) as result:
        assert result.mode == "RGBA"


@pytest.mark.parametrize("size", [0, -1, MAX_PHOTO_BYTES + 1, 20 * 1024 * 1024, True, 1.5])
def test_oversize_or_invalid_declaration_rejected(size):
    with pytest.raises(UploadError, match="^invalid_photo_size$"):
        PhotoSpec(uuid4(), uuid4(), "image/jpeg", size)


@pytest.mark.parametrize("content_type", ["image/gif", "video/mp4", "audio/mp4", "image/jpg"])
def test_unimplemented_types_fail_closed(content_type):
    with pytest.raises(UploadError, match="^unsupported_photo_type$"):
        PhotoSpec(uuid4(), uuid4(), content_type, 100)


def test_untrusted_storage_path_rejected():
    with pytest.raises(UploadError, match="^invalid_media_identity$"):
        PhotoSpec("../../other-farm", uuid4(), "image/jpeg", 100)


@pytest.mark.parametrize("data", [b"", b"not an image", b"GIF89a", b"\x00\x00\x00\x18ftypM4A"])
def test_invalid_file_rejected(data):
    with pytest.raises(UploadError):
        sanitize_photo(data, "image/jpeg")


def test_real_format_must_match_declaration():
    with pytest.raises(UploadError, match="^photo_type_mismatch$"):
        sanitize_photo(photo_bytes("PNG"), "image/jpeg")


def test_truncated_jpeg_rejected():
    with pytest.raises(UploadError, match="^invalid_photo$"):
        sanitize_photo(photo_bytes()[:-20], "image/jpeg")


def test_pixel_limit_checked_before_decode():
    with patch("farmable_backend.uploads.MAX_PHOTO_PIXELS", 10):
        with pytest.raises(UploadError, match="^photo_dimensions_too_large$"):
            sanitize_photo(photo_bytes(), "image/jpeg")


def test_animated_png_rejected():
    with Image.new("RGB", (2, 2), "red") as first, Image.new("RGB", (2, 2), "blue") as second:
        stream = BytesIO()
        first.save(stream, format="PNG", save_all=True, append_images=[second])
    with pytest.raises(UploadError, match="^animated_photo_unsupported$"):
        sanitize_photo(stream.getvalue(), "image/png")


def test_clean_output_is_bounded():
    data = photo_bytes("PNG")
    # A PNG with random/uncompressed pixels can grow when re-encoded.
    with patch("farmable_backend.uploads.MAX_PHOTO_BYTES", len(data)):
        with patch("PIL.Image.Image.save", side_effect=lambda out, **kw: out.write(data * 2)):
            with pytest.raises(UploadError, match="^clean_photo_too_large$"):
                sanitize_photo(data, "image/png")


def offline_client():
    return boto3.client(
        "s3",
        endpoint_url="https://storage.example.invalid",
        region_name="af-south-1",
        aws_access_key_id="unit-access",
        aws_secret_access_key="unit-secret",  # noqa: S106 - offline signing fixture
        config=Config(signature_version="s3v4"),
    )


def test_signed_policy_constrains_one_object_type_size_encryption_and_five_minutes():
    spec = PhotoSpec(uuid4(), uuid4(), "image/jpeg", 123)
    before = datetime.now(UTC)
    upload = PhotoStorage(offline_client(), "private-photos").prepare(spec)
    after = datetime.now(UTC)
    policy = json.loads(base64.b64decode(upload.fields["policy"]))
    conditions = policy["conditions"]
    assert {"key": spec.incoming_key} in conditions
    assert {"Content-Type": spec.content_type} in conditions
    assert ["content-length-range", 123, 123] in conditions
    assert {"x-amz-server-side-encryption": "AES256"} in conditions
    assert upload.fields["x-amz-server-side-encryption"] == "AES256"
    assert not any(isinstance(c, list) and c[0] == "starts-with" for c in conditions)
    expiry = datetime.fromisoformat(policy["expiration"].replace("Z", "+00:00"))
    assert 299 <= (expiry - before).total_seconds() <= 301
    assert 299 <= (expiry - after).total_seconds() <= 301
    assert upload.expires_in == 300
    assert "policy" not in repr(upload)
    assert "storage.example" not in repr(upload)
    assert spec.clean_key != spec.incoming_key


def storage_fixture(**overrides):
    data = photo_bytes(gps=True)
    spec = PhotoSpec(uuid4(), uuid4(), "image/jpeg", len(data))
    body = Mock(wraps=BytesIO(data))
    client = Mock()
    client.get_object.return_value = {
        "Body": body,
        "ContentLength": len(data),
        "ContentType": "image/jpeg",
        "ServerSideEncryption": "AES256",
        **overrides,
    }
    return PhotoStorage(client, "private-photos"), client, spec, body


def test_post_upload_rechecks_then_writes_only_clean_encrypted_copy():
    storage, client, spec, body = storage_fixture()
    clean = storage.sanitize(spec)
    body.read.assert_called_once_with(spec.size + 1)
    body.close.assert_called_once()
    client.get_object.assert_called_once_with(Bucket="private-photos", Key=spec.incoming_key)
    client.put_object.assert_called_once_with(
        Bucket="private-photos",
        Key=spec.clean_key,
        Body=clean.data,
        ContentType=spec.content_type,
        ServerSideEncryption="AES256",
    )


@pytest.mark.parametrize(
    "override,code",
    [
        ({"ContentLength": 20 * 1024 * 1024}, "photo_size_mismatch"),
        ({"ContentType": "image/png"}, "photo_type_mismatch"),
        ({"ServerSideEncryption": None}, "photo_encryption_missing"),
    ],
)
def test_invalid_metadata_never_read_or_published(override, code):
    storage, client, spec, body = storage_fixture(**override)
    with pytest.raises(UploadError, match=f"^{code}$"):
        storage.sanitize(spec)
    body.read.assert_not_called()
    body.close.assert_called_once()
    client.put_object.assert_not_called()


@pytest.mark.parametrize("delta", [-1, 1])
def test_stream_length_mismatch_never_published(delta):
    storage, client, spec, body = storage_fixture()
    body.read.return_value = b"x" * (spec.size + delta)
    with pytest.raises(UploadError, match="^photo_size_mismatch$"):
        storage.sanitize(spec)
    body.close.assert_called_once()
    client.put_object.assert_not_called()


def test_corrupt_uploaded_image_never_published():
    storage, client, spec, body = storage_fixture()
    body.read.return_value = b"x" * spec.size
    with pytest.raises(UploadError, match="^invalid_photo$"):
        storage.sanitize(spec)
    body.close.assert_called_once()
    client.put_object.assert_not_called()


@pytest.mark.parametrize("operation", ["get_object", "put_object", "generate_presigned_post"])
def test_sdk_errors_are_not_reflected(operation):
    storage, client, spec, _body = storage_fixture()
    getattr(client, operation).side_effect = ClientError(
        {"Error": {"Code": "AccessDenied", "Message": "DO-NOT-REFLECT-provider-secret"}},
        operation,
    )
    with pytest.raises(UploadError, match="^storage_unavailable$") as raised:
        storage.prepare(spec) if operation == "generate_presigned_post" else storage.sanitize(spec)
    assert raised.value.__cause__ is None
    assert raised.value.__suppress_context__


@pytest.mark.parametrize(
    "missing",
    [
        "BlockPublicAcls",
        "IgnorePublicAcls",
        "BlockPublicPolicy",
        "RestrictPublicBuckets",
    ],
)
def test_production_factory_rejects_public_bucket(missing):
    client = Mock()
    block = dict.fromkeys(
        ["BlockPublicAcls", "IgnorePublicAcls", "BlockPublicPolicy", "RestrictPublicBuckets"],
        True,
    )
    block[missing] = False
    client.get_public_access_block.return_value = {"PublicAccessBlockConfiguration": block}
    with patch("farmable_backend.uploads.boto3.client", return_value=client):
        with pytest.raises(UploadError, match="^private_bucket_required$"):
            create_s3_photo_storage("private-photos")


def test_production_factory_requires_verifiable_private_bucket():
    client = Mock()
    client.get_public_access_block.side_effect = ClientError(
        {"Error": {"Code": "AccessDenied", "Message": "not allowed"}},
        "GetPublicAccessBlock",
    )
    with patch("farmable_backend.uploads.boto3.client", return_value=client):
        with pytest.raises(UploadError, match="^private_bucket_unverified$"):
            create_s3_photo_storage("private-photos")
