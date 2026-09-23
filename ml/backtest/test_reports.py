"""Report acceptance tests use labelled synthetic ledgers and temporary outputs."""

import hashlib
import json
import os
import subprocess
import sys
from datetime import date
from decimal import Decimal as D

import pytest
from farmable_ml.data import Crop
from farmable_ml.decision import Decision
from farmable_ml.reports import (
    Bootstrap,
    build_report,
    metrics,
    render_sentence,
    render_table,
)


def ledger():
    crops = list(Crop)
    return tuple(
        Decision(
            date(year, 1, 1),
            crop,
            crops[(index + 1) % len(crops)],
            D(100),
            D(100 + (index - 3) * 10 + (year - 2012)),
        )
        for year in range(2012, 2015)
        for index, crop in enumerate(crops)
    )


def report():
    return build_report(
        ledger(),
        data_kind="synthetic",
        input_hashes={"fixture": "a" * 64},
        config=Bootstrap(replicates=100),
    )


def test_table_lists_every_default():
    text = render_table(report())
    defaults = [line.split("|")[1].strip() for line in text.splitlines() if line.startswith("| ")][
        2:-1
    ]
    assert defaults == sorted(crop.value for crop in Crop)


def test_slide_sentence_from_results():
    document = report()
    sentence = render_sentence(document)
    # 24 decisions, 14 winning switches, switch gains median 6, defaults span 0..100%.
    assert document["results"]["pooled"]["decisions"] == 24
    assert document["results"]["pooled"]["switch_win_rate"] == D(14) / 24
    assert document["results"]["pooled"]["median_gain_rand"] == D(6)
    assert sentence == (
        "SYNTHETIC TEST FIXTURE — NOT A REAL RESULT.\n"
        "In a historical simulation of 24 planting decisions (2012–2024), using only data "
        "available at planting time, when Farmable recommended switching away from a farmer's "
        "usual crop, the switch earned more profit 58.3% of the time, with a median increase "
        "of R 6.0 per hectare per month (ranging from 0.0% to 100.0% across the 8 starting "
        "crops). Assumes guideline yields, Joburg Market prices and Western Cape cost budgets, "
        "adjusted for inflation.\n"
    )


def test_all_defaults_exclusions_and_required_fields_exist():
    document = report()
    assert set(document["results"]) == {crop.value for crop in Crop} | {"pooled"}
    required = {
        "decisions",
        "switch_rate",
        "switch_win_rate",
        "median_gain_rand",
        "median_gain_pct",
        "p10_gain_rand",
        "worst_loss_rand",
        "median_gain_ci90",
    }
    assert all(required <= entry.keys() for entry in document["results"].values())
    assert set(document["excluded"]) == {"beetroot", "pumpkins"}
    assert all(document["excluded"].values())


def test_nonpositive_defaults_keep_losses_and_explain_percent_denominator():
    rows = (
        Decision(date(2012, 1, 1), Crop.CABBAGE, Crop.CARROTS, D(-10), D(-20)),
        Decision(date(2013, 1, 1), Crop.CABBAGE, Crop.CARROTS, D(0), D(10)),
        Decision(date(2014, 1, 1), Crop.CABBAGE, Crop.CARROTS, D(100), D(120)),
        Decision(date(2015, 1, 1), Crop.CABBAGE, Crop.CABBAGE, D(100), D(100)),
    )
    result = metrics(rows, Bootstrap(replicates=100))
    assert result["switch_rate"] == D("0.75")
    assert result["median_gain_rand"] == 10
    assert result["median_gain_pct"] == 20
    assert result["percentage_excluded_switches"] == 2
    assert result["worst_loss_rand"] == -10
    assert result["p10_gain_rand"] == -6


def test_no_switches_are_undefined_and_do_not_generate_a_headline():
    rows = (Decision(date(2012, 1, 1), Crop.CABBAGE, Crop.CABBAGE, D(2), D(2)),)
    document = build_report(rows, input_hashes={"fixture": "a" * 64}, data_kind="synthetic")
    assert document["results"]["pooled"]["switch_rate"] == 0
    assert document["results"]["pooled"]["switch_win_rate"] is None
    assert "INSUFFICIENT EVIDENCE" in render_sentence(document)
    assert document["results"]["carrots"]["decisions"] == 0


def test_duplicate_decisions_fail():
    with pytest.raises(ValueError, match="duplicate"):
        build_report(ledger() * 2, input_hashes={"fixture": "a" * 64}, data_kind="synthetic")


def test_reproducible_output(tmp_path):
    # Different hash seeds and input orders in genuinely separate interpreters.
    program = """
import sys
from datetime import date
from decimal import Decimal as D
from pathlib import Path
from farmable_ml.data import Crop
from farmable_ml.decision import Decision
from farmable_ml.reports import Bootstrap, build_report, write_synthetic_report
crops = list(Crop)
rows = tuple(Decision(date(year, 1, 1), crop, crops[(index + 1) % 8],
                      D(100), D(100 + index * 10 + year - 2012))
             for year in range(2012, 2015) for index, crop in enumerate(crops))
if sys.argv[2] == 'reverse':
    rows = tuple(reversed(rows))
report = build_report(rows, data_kind='synthetic', input_hashes={'fixture': 'a' * 64},
                      config=Bootstrap(replicates=100))
write_synthetic_report(report, Path(sys.argv[1]))
"""
    for number, order in [(1, "forward"), (2, "reverse")]:
        subprocess.run(  # noqa: S603 - fixed Python fixture and temporary output paths
            [sys.executable, "-c", program, str(tmp_path / str(number)), order],
            check=True,
            env={**os.environ, "PYTHONHASHSEED": str(number)},
            capture_output=True,
            text=True,
        )
    left = {path.name: path.read_bytes() for path in (tmp_path / "1").iterdir()}
    right = {path.name: path.read_bytes() for path in (tmp_path / "2").iterdir()}
    assert left == right
    assert set(left) == {
        "decision_backtest.json",
        "decision_backtest.md",
        "slide_sentence.txt",
        "manifest.json",
    }
    manifest = json.loads(left["manifest.json"])
    for name, expected in manifest["artifacts"].items():
        assert hashlib.sha256(left[name]).hexdigest() == expected
