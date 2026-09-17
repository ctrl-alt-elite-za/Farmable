import subprocess
import sys
from pathlib import Path


def test_raw_sql_check_detects_text(tmp_path):
    # Construct a forbidden fixture at runtime; don't weaken the production scanner.
    fixture = tmp_path / "bad.py"
    fixture.write_text('session.execute(text("SELECT 1"))\n', encoding="utf-8")
    root = Path(__file__).resolve().parents[3]
    result = subprocess.run(  # noqa: S603
        [sys.executable, str(root / "scripts/check_no_raw_sql.py"), str(tmp_path)],
        cwd=root,
        capture_output=True,
        text=True,
        check=False,
    )
    assert result.returncode == 1
    assert "Hand-written SQL found" in result.stderr
    assert "bad.py" in result.stdout + result.stderr
