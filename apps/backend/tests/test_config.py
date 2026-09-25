import pytest
from farmable_backend.config import Settings
from pydantic import SecretStr, ValidationError


@pytest.mark.parametrize("value", ["", "   ", "replace-with-a-local-secret"])
def test_export_token_secret_rejects_empty_and_example_placeholders(value: str) -> None:
    with pytest.raises(ValidationError, match="EXPORT_TOKEN_SECRET"):
        Settings(
            database_url=SecretStr("postgresql+psycopg://unit:unit@localhost/unit"),
            export_token_secret=SecretStr(value),
        )
