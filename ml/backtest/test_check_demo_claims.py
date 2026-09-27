"""The demo-claims check (#26): only backed statistics, only when evidence suffices."""

import json
from pathlib import Path

import check_demo_claims as check
import pytest

RESULTS = {
    "results": {
        "pooled": {
            "median_gain_rand": 91473.19171696156,
            "median_gain_pct": 404.03381705414097,
            "switch_win_rate": 0.9693251533742331,
            "median_gain_ci90": [82403.25354157208, 95553.11931723962],
        }
    },
    "bootstrap": {"seed": 20, "minimum_valid_fraction": 0.9},
}


def run(tmp_path: Path, sentence: str) -> Path:
    folder = tmp_path / "run"
    folder.mkdir(exist_ok=True)
    (folder / "slide_sentence.txt").write_text(sentence, encoding="utf-8")
    (folder / "decision_backtest.json").write_text(json.dumps(RESULTS), encoding="utf-8")
    return folder


def script(tmp_path: Path, text: str) -> Path:
    path = tmp_path / "demo-script.md"
    path.write_text(text, encoding="utf-8")
    return path


def verdict(tmp_path: Path, sentence: str, text: str, monkeypatch) -> int:
    folder = run(tmp_path, sentence)
    monkeypatch.setattr(check, "RESULTS", folder.parent)
    return check.main([str(script(tmp_path, text)), "--run", folder.name])


SUFFICIENT = "Switching won in 97% of decisions, a median gain of R91 473."


def test_figures_from_the_results_pass_at_the_precision_written(tmp_path, monkeypatch):
    text = (
        "In the backtest the switch won 96.9% of the time, for a median gain of "
        "R91,473 (R82 403 to R95 553), or 404% more.\n"
    )
    assert verdict(tmp_path, SUFFICIENT, text, monkeypatch) == 0


@pytest.mark.parametrize(
    "claim",
    ["Farmers earn 45% more.", "A typical gain is R120 000.", "Switching wins 97.1 percent."],
)
def test_an_unbacked_figure_fails(tmp_path, monkeypatch, capsys, claim):
    assert verdict(tmp_path, SUFFICIENT, f"Intro.\n{claim}\n", monkeypatch) == 1
    assert "demo-script.md:2:" in capsys.readouterr().err


def test_configuration_numbers_are_not_evidence(tmp_path, monkeypatch):
    # The bootstrap's 0.9 is a setting, not a finding.
    assert verdict(tmp_path, SUFFICIENT, "It is right 90% of the time.\n", monkeypatch) == 1


def test_insufficient_evidence_allows_no_backtest_figure(tmp_path, monkeypatch, capsys):
    sentence = "INSUFFICIENT EVIDENCE: switch statistics are undefined."
    assert verdict(tmp_path, sentence, "A median gain of R91 473.\n", monkeypatch) == 1
    assert "INSUFFICIENT EVIDENCE" in capsys.readouterr().err
    assert verdict(tmp_path, sentence, "No numbers are claimed here.\n", monkeypatch) == 0


def test_what_the_farmer_says_or_the_app_shows_is_not_a_claim(tmp_path, monkeypatch):
    text = (
        "The farmer says `My budget is R3 000, only 20% for spinach`.\n"
        "```\nPlan option 1 of 3: margin R3,047 (45%)\n```\n"
    )
    sentence = "INSUFFICIENT EVIDENCE: switch statistics are undefined."
    assert verdict(tmp_path, sentence, text, monkeypatch) == 0


def test_the_committed_run_is_found_and_read():
    run = check.latest_run()
    assert (run / "decision_backtest.json").is_file()
    assert isinstance(check.evidence(run), check.Evidence)


def test_the_committed_demo_script_quotes_only_backed_figures():
    script = Path(__file__).resolve().parents[2] / "docs" / "demo-script.md"
    assert check.main([str(script)]) == 0
