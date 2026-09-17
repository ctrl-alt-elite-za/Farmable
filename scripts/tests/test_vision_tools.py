import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "apps/ml-service"))

from vision.check_split import split_sessions, validate_labels
from vision.eval_weights import fit_range, load_measurements
from vision.train import report_for


def test_split_check_rejects_shared_filming_session(tmp_path: Path) -> None:
    train, test = tmp_path / "train", tmp_path / "test"
    train.mkdir()
    test.mkdir()
    (train / "morning_1.jpg").touch()
    (test / "morning_2.jpg").touch()
    manifest = tmp_path / "sessions.csv"
    manifest.write_text("image,session_id\nmorning_1.jpg,s1\nmorning_2.jpg,s1\n", encoding="utf-8")
    train_sessions, test_sessions = split_sessions(train, test, manifest)
    assert train_sessions & test_sessions == {"s1"}


def test_weight_fit_requires_twenty_real_measurements(tmp_path: Path) -> None:
    path = tmp_path / "cabbage.csv"
    path.write_text("diameter_cm,weight_g\n10,500\n", encoding="utf-8")
    with pytest.raises(ValueError, match="at least 20"):
        load_measurements(path)


def test_weight_fit_reports_holdout_coverage() -> None:
    values = [(10.0 + index, 100.0 + 10 * index) for index in range(25)]
    result = fit_range(values)
    assert result["held_out"] == 5
    assert result["coverage"] == 1.0


def test_label_validator_rejects_missing_label(tmp_path: Path) -> None:
    images = tmp_path / "train" / "images"
    images.mkdir(parents=True)
    (images / "frame.jpg").touch()
    with pytest.raises(ValueError, match="missing label"):
        validate_labels(images)


def test_training_report_has_per_class_and_session_contract() -> None:
    report = report_for("v1", 42, 10, {}, ["train-a"], ["test-a"])
    assert set(report["classes"]) == {"plant", "crop_head_or_fruit", "check_suggested"}
    assert set(report["classes"]["plant"]) == {"precision", "recall", "map50"}
    assert report["train_sessions"] == ["train-a"]
    assert report["test_sessions"] == ["test-a"]
