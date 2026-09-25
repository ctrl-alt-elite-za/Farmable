import os

import pytest
from farmable_backend.config import Settings
from pydantic import SecretStr

# Production requires this value at startup. Tests use a deterministic synthetic
# value so Settings() calls made by integration helpers exercise the same contract.
os.environ.setdefault("EXPORT_TOKEN_SECRET", "test-export-token-secret-32-bytes")


@pytest.fixture
def settings() -> Settings:
    # Fake credentials; unit tests inject dependency status and never connect.
    return Settings(
        database_url=SecretStr("postgresql+psycopg://unit:unit@localhost/unit"),
        export_token_secret=SecretStr("test-export-token-secret-32-bytes"),
        commit_sha="test-sha",
    )
