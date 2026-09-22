"""New database races must be selected and have fixtures in the disposable image."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def test_forecast_races_are_explicitly_selected():
    script = (ROOT / "scripts/test-integration.sh").read_text()
    lines = [line for line in script.splitlines() if "run --rm tests pytest" in line]
    for name in ("test_forecast_postgres.py", "test_voice_sessions_postgres.py"):
        assert any(
            name in line and "-m integration" in line and " -k " not in line for line in lines
        )


def test_synthetic_artifacts_only_enter_testing_image():
    dockerfile = (ROOT / "apps/backend/Dockerfile").read_text()
    testing = dockerfile.split("FROM base AS testing\n", 1)[1].split("FROM base AS runtime", 1)[0]
    assert "COPY ml/forecast/fixtures ml/forecast/fixtures" in testing
    assert "ml/forecast" not in dockerfile.split("FROM base AS testing", 1)[0]
    assert "ml/forecast" not in dockerfile.split("FROM base AS runtime", 1)[1]
