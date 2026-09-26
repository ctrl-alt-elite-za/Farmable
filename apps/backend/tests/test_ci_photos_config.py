"""The CI stack's disposable photo storage (#11) is refused outside CI."""

import pytest
from farmable_backend.ci_photos import CiPhotos
from farmable_backend.config import Settings
from farmable_backend.gcs_photos import create_photos
from pydantic import ValidationError

DATABASE_URL = "postgresql+psycopg://user:secret@database/farmable"


@pytest.mark.parametrize("environment", ["staging", "production"])
def test_test_storage_is_refused_outside_ci(environment):
    with pytest.raises(ValidationError, match="ENVIRONMENT=ci or development"):
        Settings(
            database_url=DATABASE_URL,
            environment=environment,
            photo_bucket="photos",
            photo_test_storage_url="http://photo-storage:9000",
        )


def test_production_default_never_builds_test_storage():
    settings = Settings(database_url=DATABASE_URL)
    assert settings.photo_test_storage_url is None
    assert create_photos(settings) is None  # no bucket: storage disabled, as before


def test_ci_builds_test_storage_signed_for_the_emulator_host():
    settings = Settings(
        database_url=DATABASE_URL,
        environment="ci",
        photo_bucket="photos",
        photo_test_storage_url="http://photo-storage:9000",
        photo_test_storage_public_url="http://10.0.2.2:9000",
        photo_test_storage_user="user",
        photo_test_storage_password="password",  # noqa: S106 - fake
    )
    photos = create_photos(settings)
    try:
        assert isinstance(photos, CiPhotos)
        assert photos.client.meta.endpoint_url == "http://photo-storage:9000"
        assert photos.signer.meta.endpoint_url == "http://10.0.2.2:9000"
    finally:
        photos.close()
