"""Reuse the disposable-schema backend fixtures, never a developer database."""

import sys
from pathlib import Path

TESTS = Path(__file__).resolve().parents[2] / "apps/backend/tests"
sys.path.insert(0, str(TESTS))
sys.path.insert(0, str(TESTS / "integration"))

from test_photo_sync_postgres import pg  # noqa: E402, F401 -- shared pytest fixture
