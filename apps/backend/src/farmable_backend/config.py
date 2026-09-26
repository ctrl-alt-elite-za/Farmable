from typing import Literal

from pydantic import SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore", hide_input_in_errors=True)

    database_url: SecretStr
    log_level: Literal["debug", "info", "warning", "error", "critical"] = "info"
    commit_sha: str = "unknown"
    photo_bucket: str | None = None
    photo_signer_email: str | None = None
    # Disposable MinIO for the CI stack only (ci_photos.py); refused elsewhere.
    environment: Literal["development", "ci", "staging", "production"] = "production"
    photo_test_storage_url: str | None = None
    photo_test_storage_public_url: str | None = None
    photo_test_storage_user: str | None = None
    photo_test_storage_password: SecretStr | None = None
    diagnosis_enabled: bool = False
    forecast_data_mode: Literal["disabled", "sample", "historical", "retrospective"] = "disabled"

    @field_validator("database_url")
    @classmethod
    def postgres_credentials(cls, value: SecretStr) -> SecretStr:
        try:
            url = make_url(value.get_secret_value())
        except Exception:
            raise ValueError("DATABASE_URL must be a PostgreSQL URL") from None
        if url.drivername != "postgresql+psycopg" or not url.username or not url.password:
            raise ValueError("DATABASE_URL requires postgresql+psycopg and credentials")
        return value

    @model_validator(mode="after")
    def test_storage_only_in_ci(self) -> "Settings":
        if self.photo_test_storage_url is not None and self.environment not in (
            "ci",
            "development",
        ):
            raise ValueError("PHOTO_TEST_STORAGE_URL requires ENVIRONMENT=ci or development")
        return self
