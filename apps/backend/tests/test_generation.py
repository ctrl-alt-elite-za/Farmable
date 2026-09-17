import json
from pathlib import Path

from farmable_backend.main import create_app


def test_checked_in_openapi_matches_application():
    root = Path(__file__).resolve().parents[3]
    schema = json.loads((root / "packages/api-client/openapi.json").read_text(encoding="utf-8"))
    assert schema == create_app().openapi()
