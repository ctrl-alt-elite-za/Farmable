from typing import Literal

from pydantic import SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url


class Settings(BaseSettings):
    model_config = SettingsConfigDict(extra="ignore", hide_input_in_errors=True)

    database_url: SecretStr
    log_level: Literal["debug", "info", "warning", "error", "critical"] = "info"
    commit_sha: str = "unknown"
    export_token_secret: SecretStr
    photo_bucket: str | None = None
    photo_signer_email: str | None = None
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

    @field_validator("export_token_secret")
    @classmethod
    def export_secret_required(cls, value: SecretStr) -> SecretStr:
        if not value.get_secret_value().strip():
            raise ValueError("EXPORT_TOKEN_SECRET must not be empty")
        return value
