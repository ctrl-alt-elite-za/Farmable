"""Shared photo retry budget and fixed, provider-independent public failures."""

from typing import Literal

RETRY_DELAYS = (5, 30, 120)
MAX_CLAIMS = len(RETRY_DELAYS) + 1
# `signer_required` and `workload_credentials_required` come from
# create_gcs_photos, not from a photo. They describe the deployment and are
# fixed by an operator editing configuration, so they must stay retryable:
# classifying them as permanent fails the upload on the worker's first pass and
# then locks the farmer's local_media_id behind uq_photo_uploads_local, which
# makes that photo unuploadable from the phone for good.
TRANSIENT_ERRORS = frozenset(
    {
        "incoming_missing",
        "storage_unavailable",
        "private_bucket_unverified",
        "private_bucket_required",
        "signer_required",
        "workload_credentials_required",
    }
)
RECOVERABLE_ERRORS = TRANSIENT_ERRORS | {"retry_exhausted"}
INVALID_PHOTO_ERRORS = frozenset(
    {
        "invalid_photo",
        "photo_size_mismatch",
        "photo_type_mismatch",
        "invalid_photo_size",
        "photo_dimensions_too_large",
        "animated_photo_unsupported",
        "clean_photo_too_large",
        "unsupported_photo_type",
    }
)
PublicPhotoError = Literal[
    "temporarily_unavailable", "invalid_photo", "target_unavailable", "upload_failed"
]


def public_photo_error(code: str | None) -> PublicPhotoError | None:
    if code is None:
        return None
    if code in RECOVERABLE_ERRORS:
        return "temporarily_unavailable"
    if code in INVALID_PHOTO_ERRORS:
        return "invalid_photo"
    if code == "scope_unavailable":
        return "target_unavailable"
    return "upload_failed"
