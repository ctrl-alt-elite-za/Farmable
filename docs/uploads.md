# Upload storage: independent slice of issue #17

This is a storage/photo-validation boundary, **not the completed issue**. No
authentication endpoints, database models, migrations, worker jobs, or phone
queue are added. It deliberately leaves those shared surfaces untouched while
their dependencies and feature PRs are outstanding.

## Supported behavior

- JPEG and PNG, 1–5,000,000 bytes. Unsupported types, including M4A pending real
  audio validation, fail closed. Animated PNG and images over 20 million pixels
  are rejected to bound worker memory usage.
- `PhotoSpec` contains server-issued farm/media UUIDs, an exact content type and
  a declared byte length. Persist it in the future media record; never rebuild
  it from completion-request data or accept a caller-provided storage key.
- `PhotoStorage.prepare` returns a **presigned multipart POST**, not a PUT URL.
  Send every returned form field unchanged, followed by the single `file` part.
  The signed policy binds one incoming key, exact length and type, and a
  five-minute expiry. Phone clients must support this multipart contract.
- `PhotoStorage.sanitize` reads at most the declared length plus one byte and
  rechecks storage metadata, actual length and decoded image format. It loads
  the pixels (rejecting corrupt/truncated files), applies EXIF orientation, then
  re-encodes a fresh image without EXIF, XMP, text or other source metadata.
  PNG transparency is preserved; output size is also bounded to 5,000,000 bytes.
- Incoming and cleaned keys are separate. A replayed upload form cannot target
  the clean key or a different farm/media key. Only the worker writes the clean
  key. Sanitization failure publishes no cleaned object.
- Production uses `create_s3_photo_storage`: IAM credentials, SigV4, finite SDK
  timeouts/retries, and all four S3 Block Public Access settings required. Both
  incoming policy and cleaned writes require SSE-S3 (`AES256`); reads recheck
  encryption. Provision a dedicated private bucket with least-privilege IAM
  and TLS in staging infrastructure first. This module never provisions it.

SDK calls are synchronous: run them in the worker/thread, not on the async API
event loop. Errors are fixed codes, never reflected SDK messages. Do not log
form fields/URLs, file bytes, provider responses or credentials; bearer fields
and file bytes are excluded from dataclass representations.

## Verification

```sh
uv run pytest apps/backend/tests/test_upload_storage.py -q
bash scripts/test-upload-storage.sh
```

The second command builds the official security-patched MinIO source release
because that release has no official prebuilt container. Builds are cached.
It creates random test credentials and a unique Compose project, has no host
ports, isolates the runtime network, and removes only that project's containers
on exit. Object data is ephemeral container data; no developer DB or cloud
account is touched. The fixture runs unprivileged.

Disposable MinIO has **no KMS**: only this local fixture explicitly passes
`local_test_without_kms=True`. Local integration tests therefore prove private
access and signed policy enforcement, **not encryption at rest**. Production
encryption and bucket checks are covered with injected SDK tests and still need
a real staging acceptance check after bucket provisioning.

Real storage tests cover upload → sanitized private copy, GPS removal, wrong
key/type/size rejection, already-expired policy rejection (without a five-minute
sleep), anonymous read rejection, and corrupt-file rejection. Ordinary CI runs
the unit tests; the isolated MinIO command is an additional review check, not a
new required branch-protection check. It is not `test_upload_flow`'s pending
authenticated HTTP → job → media-ready acceptance test.

## Remaining before issue #17 can close

Schema #8 and auth #9 must supply farm ownership and durable media/job records.
Then add upload/complete/job endpoints, 30/min/user rate limiting, exactly-once
completion claims, job states with three retries/backoff, failed-job staging
listing, and one-hour abandonment/incoming-object cleanup. A successful storage
write alone must never mark a media record ready; persist success only after it
returns, with idempotent recovery if a worker dies between those operations.

M4A type/track validation, the persistent phone upload queue, restart/offline
Maestro coverage, and the complete acceptance flow are also pending. Do not
close #17 or advertise production/mobile upload support from this slice.

Policy choice follows [AWS POST policy constraints](https://docs.aws.amazon.com/AmazonS3/latest/developerguide/sigv4-HTTPPOSTConstructPolicy.html).
Metadata handling uses [Pillow EXIF orientation support](https://pillow.readthedocs.io/en/stable/reference/ImageOps.html#PIL.ImageOps.exif_transpose).
The local fixture follows the [official patched source release](https://github.com/minio/minio/releases/tag/RELEASE.2025-10-15T17-29-55Z);
it is not a recommendation to deploy an archived MinIO project in production.
