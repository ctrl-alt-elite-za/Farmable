"""The Colab workflow stays reviewable, credential-free and tied to shared code."""

import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
NOTEBOOK = ROOT / "ml/notebooks/forecast_and_backtest.ipynb"


def test_colab_notebook_is_clean_and_uses_registered_runner():
    document = json.loads(NOTEBOOK.read_text(encoding="utf-8"))
    assert document["nbformat"] == 4
    code = "\n".join(
        "".join(cell["source"]) for cell in document["cells"] if cell["cell_type"] == "code"
    )
    assert all(cell.get("execution_count") is None for cell in document["cells"])
    assert all(cell.get("outputs", []) == [] for cell in document["cells"])
    assert "FARMABLE_REVISION" in code
    assert "check_protocol_first.py" in code
    assert "run_retrospective.py" in code
    assert "pytest" in code
    assert "--workbooks" in code
    assert "--output" in code
    assert "/content/issue20-colab-results" in code
    assert "--python" in code
    assert code.count("--no-sync") == 3
    assert not any(token in code.lower() for token in ("password=", "api_key", "access_token"))
