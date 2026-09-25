from typing import Literal

from pydantic import Field, SecretStr, field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict
from sqlalchemy.engine import make_url


class ProxySettings(BaseSettings):
    """Network settings the ASGI app needs before its lifespan builds ``Settings``."""

    model_config = SettingsConfigDict(extra="ignore", hide_input_in_errors=True)

    # Number of trusted reverse proxies in front of the API that each append the
    # address they received the request from to X-Forwarded-For. 0 (the default,
    # for local and Compose) trusts only the socket peer. Cloud Run's front end
    # appends the caller's address, so its deployment sets 1; everything to the
    # left of the trusted entries is client-supplied and never used.
    trusted_proxy_hops: int = Field(0, ge=0, le=2)


class DatabaseSettings(ProxySettings):
    """Settings for processes that never sign export links (migrations, jobs).

    They run under narrower identities than the API, so they must neither need
    nor be granted ``EXPORT_TOKEN_SECRET``.
    """

    database_url: SecretStr
    log_level: Literal["debug", "info", "warning", "error", "critical"] = "info"
    commit_sha: str = "unknown"
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


class Settings(DatabaseSettings):
    export_token_secret: SecretStr

    @field_validator("export_token_secret")
    @classmethod
    def export_secret_required(cls, value: SecretStr) -> SecretStr:
        secret = value.get_secret_value().strip()
        if not secret or secret.startswith("replace-with-"):
            raise ValueError("EXPORT_TOKEN_SECRET must be a non-placeholder secret")
        return SecretStr(secret)
