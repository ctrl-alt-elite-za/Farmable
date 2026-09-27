from typing import Literal, Self

from pydantic import Field, SecretStr, field_validator, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict

SERVICES = (
    "twilio",
    "turnstile",
    "azure_stt",
    "azure_tts",
    "gemini",
    "crop_health",
    "soilgrids",
    "open_meteo",
    "maps",
)
TIMEOUTS = dict(zip(SERVICES, (10.0, 5.0, 15.0, 10.0, 60.0, 20.0, 10.0, 10.0, 10.0), strict=True))


class ServiceSettings(BaseSettings):
    # Deployment injects decrypted SSM parameters. CI never automatically reads .env.
    model_config = SettingsConfigDict(
        extra="forbid", hide_input_in_errors=True, env_ignore_empty=True
    )

    environment: Literal["development", "ci", "staging", "production"] = "production"
    integrations_mode: Literal["disabled", "fake", "live"] = "disabled"
    fault_twilio: bool = False
    fault_turnstile: bool = False
    fault_azure_stt: bool = False
    fault_azure_tts: bool = False
    fault_gemini: bool = False
    fault_crop_health: bool = False
    fault_soilgrids: bool = False
    fault_open_meteo: bool = False
    fault_maps: bool = False
    twilio_account_sid: str | None = Field(
        default=None, pattern=r"^AC[0-9a-fA-F]{32}$", max_length=34
    )
    twilio_verify_service_sid: str | None = Field(
        default=None, pattern=r"^VA[0-9a-fA-F]{32}$", max_length=34
    )
    twilio_auth_token: SecretStr | None = Field(default=None, repr=False)
    twilio_fraud_guard_confirmed: bool = False
    turnstile_secret: SecretStr | None = Field(default=None, repr=False)
    turnstile_hostname: str | None = Field(default=None, max_length=253)
    azure_speech_key: SecretStr | None = Field(default=None, repr=False)
    azure_speech_resource: str | None = Field(
        default=None, pattern=r"^[a-zA-Z0-9-]{1,63}$", max_length=63
    )
    azure_speech_region: str | None = Field(
        default=None, pattern=r"^[a-z0-9-]{1,32}$", max_length=32
    )
    gemini_api_key: SecretStr | None = Field(default=None, repr=False)
    gemini_model: str | None = Field(
        default=None, pattern=r"^[a-zA-Z0-9._-]{1,128}$", max_length=128
    )
    gemini_live_enabled: bool = False
    gemini_live_model: str | None = Field(
        default=None, pattern=r"^[a-zA-Z0-9._-]{1,128}$", max_length=128
    )
    crop_health_api_key: SecretStr | None = Field(default=None, repr=False)
    maps_server_api_key: SecretStr | None = Field(default=None, repr=False)
    # Verification codes (#7). infra/set-secret.sh checks the same patterns before
    # upload, because a value that fails them stops the backend from starting.
    infobip_base_url: str | None = Field(
        default=None, pattern=r"^([a-z0-9-]+\.)?api\.infobip\.com$", max_length=253
    )
    infobip_api_key: SecretStr | None = Field(default=None, repr=False)
    infobip_sms_sender: str | None = Field(
        default=None, pattern=r"^(\+?[0-9]{3,15}|[A-Za-z0-9 ]{1,11})$", max_length=16
    )
    infobip_email_sender: str | None = Field(
        default=None, pattern=r"^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$", max_length=254
    )
    # Email codes by SMTP instead of Infobip email. Gmail by default, so only the
    # user, app password and from address need setting; set-secret.sh mirrors these.
    smtp_host: str = Field(
        default="smtp.gmail.com", pattern=r"^[a-zA-Z0-9.-]{1,253}$", max_length=253
    )
    smtp_port: int = Field(default=587, ge=1, le=65535)
    smtp_tls_mode: Literal["starttls", "ssl"] = "starttls"
    smtp_user: str | None = Field(
        default=None, pattern=r"^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$", max_length=254
    )
    smtp_password: SecretStr | None = Field(default=None, repr=False)
    email_from_name: str = Field(default="Almanac", pattern=r"^[^\r\n<>\"]{1,78}$")
    email_from_address: str | None = Field(
        default=None, pattern=r"^[^@\s<>]+@[^@\s<>]+\.[^@\s<>]+$", max_length=254
    )

    @field_validator("smtp_password", mode="before")
    @classmethod
    def app_password_without_spaces(cls, value: object) -> object:
        # Google shows an app password as four groups of four; SMTP wants it joined.
        if isinstance(value, str):
            return "".join(value.split())
        return value

    @field_validator("infobip_base_url", mode="before")
    @classmethod
    def infobip_host_only(cls, value: object) -> object:
        # The Infobip portal shows the base URL with its scheme; keep only the host.
        if isinstance(value, str):
            return value.strip().removeprefix("https://").rstrip("/").lower()
        return value

    @model_validator(mode="after")
    def safe_test_controls(self) -> Self:
        if self.environment not in {"ci", "staging"}:
            if any(getattr(self, "fault_" + service) for service in SERVICES):
                raise ValueError("Fault flags require ENVIRONMENT=ci or staging")
            if self.integrations_mode == "fake":
                raise ValueError("Fake services require ENVIRONMENT=ci or staging")
        return self

    def fault(self, service: str) -> bool:
        if service not in SERVICES:
            raise ValueError("Unknown service")
        return bool(getattr(self, "fault_" + service))
