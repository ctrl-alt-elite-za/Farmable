import pytest
from farmable_backend.config import Settings
from pydantic import SecretStr


@pytest.fixture
def settings() -> Settings:
    # Fake credentials; unit tests inject dependency status and never connect.
    return Settings(
        database_url=SecretStr("postgresql+psycopg://unit:unit@localhost/unit"),
        commit_sha="test-sha",
        export_token_secret=SecretStr("unit-export-token-secret"),
    )
