"""Training contract regressions; no private data, SDK downloads or real training."""

import json
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import Mock

import pytest
import yaml

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "apps/ml-service"))

from vision import train  # noqa: E402


@pytest.mark.parametrize("class_ids", [[0, 2], [1, 2], [2], [0, 1, 2], [2, 0], []])
def test_report_metrics_use_actual_class_ids(class_ids: list[int]) -> None:
    results = [(0.1 + class_id / 10, 0.4, 0.5, 0.6) for class_id in class_ids]
    metric = Mock(side_effect=lambda position: results[position])
    box = SimpleNamespace(ap_class_index=class_ids, class_result=metric)
    for class_id in range(3):
        result = train.class_result(box, class_id)
        expected = 0.1 + class_id / 10 if class_id in class_ids else None
        assert result["precision"] == expected
        assert result["recall"] == (0.4 if class_id in class_ids else None)
        assert result["map50"] == (0.5 if class_id in class_ids else None)
    assert [call.args[0] for call in metric.call_args_list] == [
        class_ids.index(class_id) for class_id in range(3) if class_id in class_ids
    ]


def test_report_metrics_without_a_box_are_unmeasured() -> None:
    assert train.class_result(None, 1) == {"precision": None, "recall": None, "map50": None}


@pytest.fixture
def training_run(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> SimpleNamespace:
    dataset = tmp_path / "dataset"
    for split in ("train", "test"):
        (dataset / split / "images").mkdir(parents=True)
    config = dataset / "data.yaml"
    config.write_text(
        yaml.safe_dump(
            {
                "path": ".",
                "train": "train/images",
                "val": "train/images",
                "test": "test/images",
                "names": train.CLASSES,
            }
        ),
        encoding="utf-8",
    )
    calls: list[tuple[str, dict[str, object], dict[str, object]]] = []
    constructors = Mock()

    class FakeYOLO:
        def __init__(self, model: str) -> None:
            constructors(model)

        def train(self, **options: object) -> SimpleNamespace:
            data = yaml.safe_load(Path(str(options["data"])).read_text(encoding="utf-8"))
            calls.append(("train", options, data))
            return SimpleNamespace(results_dict={})

        def val(self, **options: object) -> SimpleNamespace:
            data = yaml.safe_load(Path(str(options["data"])).read_text(encoding="utf-8"))
            calls.append(("test", options, data))
            box = SimpleNamespace(
                ap_class_index=[0, 2],
                class_result=lambda position: [(0.1, 0.2, 0.3, 0.4), (0.9, 0.8, 0.7, 0.6)][
                    position
                ],
            )
            return SimpleNamespace(results_dict={}, box=box)

    monkeypatch.setitem(sys.modules, "ultralytics", SimpleNamespace(YOLO=FakeYOLO))
    # The dataset validators have their own fixture tests. Here we isolate the
    # binding between their audited directories and the SDK's actual inputs.
    split_check = Mock(return_value=({"train-session"}, {"test-session"}))
    monkeypatch.setattr(train, "split_sessions", split_check)
    monkeypatch.setattr(train, "validate_labels", Mock(return_value={0: 1, 1: 1, 2: 1}))
    monkeypatch.setattr(
        train,
        "count_crop_images",
        Mock(return_value={"cabbage": 300, "tomato": 300, "spinach": 300}),
    )
    report_dir, runs_dir = tmp_path / "reports", tmp_path / "runs"
    monkeypatch.setattr(
        sys,
        "argv",
        [
            "train.py",
            "--version",
            "v1",
            "--data",
            str(config),
            "--train-images",
            str(dataset / "train/images"),
            "--test-images",
            str(dataset / "test/images"),
            "--manifest",
            str(dataset / "sessions.csv"),
            "--report-dir",
            str(report_dir),
            "--runs-dir",
            str(runs_dir),
        ],
    )
    return SimpleNamespace(
        dataset=dataset,
        config=config,
        calls=calls,
        constructors=constructors,
        split_check=split_check,
        report_dir=report_dir,
        runs_dir=runs_dir,
    )


@pytest.mark.parametrize("split", ["train", "test"])
def test_training_rejects_a_yaml_dataset_mismatch_before_loading_model(
    training_run: SimpleNamespace, split: str, capsys: pytest.CaptureFixture[str]
) -> None:
    other = training_run.dataset / "unrelated/images"
    other.mkdir(parents=True)
    config = yaml.safe_load(training_run.config.read_text(encoding="utf-8"))
    config[split] = str(other)
    training_run.config.write_text(yaml.safe_dump(config), encoding="utf-8")
    with pytest.raises(SystemExit) as error:
        train.main()
    assert error.value.code == 2
    assert split in capsys.readouterr().err
    training_run.constructors.assert_not_called()
    assert not training_run.calls
    assert not training_run.report_dir.exists()


def test_training_uses_one_absolute_audited_snapshot_for_training_and_test(
    training_run: SimpleNamespace, tmp_path: Path, monkeypatch: pytest.MonkeyPatch
) -> None:
    # No path may depend on the working directory or SDK dataset settings.
    monkeypatch.chdir(tmp_path)
    original = training_run.config.read_bytes()
    assert train.main() == 0
    assert [stage for stage, _, _ in training_run.calls] == ["train", "test"]
    snapshots = [options["data"] for _, options, _ in training_run.calls]
    assert snapshots[0] == snapshots[1]
    assert Path(str(snapshots[0])) != training_run.config
    for _, _, data in training_run.calls:
        assert data["train"] == str((training_run.dataset / "train/images").resolve())
        assert data["test"] == str((training_run.dataset / "test/images").resolve())
        assert data["val"] == str((training_run.dataset / "train/images").resolve())
        assert data["names"] == train.CLASSES
    assert training_run.config.read_bytes() == original
    report = json.loads((training_run.report_dir / "v1.json").read_text(encoding="utf-8"))
    assert report["train_sessions"] == ["train-session"]
    assert report["test_sessions"] == ["test-session"]
    assert report["classes"]["crop_head_or_fruit"]["precision"] is None
    assert report["classes"]["check_suggested"]["precision"] == 0.9


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("path", None),
        ("names", list(reversed(train.CLASSES))),
        ("nc", 4),
        ("train", None),
        ("test", ["test/images"]),
        ("train", "data.yaml"),
        ("val", "missing/images"),
        ("val", ""),
        ("test", "https://example.test/images"),
    ],
)
def test_invalid_dataset_contracts_fail_before_model_loading(
    training_run: SimpleNamespace, field: str, value: object
) -> None:
    config = yaml.safe_load(training_run.config.read_text(encoding="utf-8"))
    config[field] = value
    training_run.config.write_text(yaml.safe_dump(config), encoding="utf-8")
    with pytest.raises(SystemExit) as error:
        train.main()
    assert error.value.code == 2
    training_run.constructors.assert_not_called()
    training_run.split_check.assert_not_called()
    assert not training_run.report_dir.exists()
    assert not training_run.runs_dir.exists()


@pytest.mark.parametrize("content", ["[broken", "- not-a-mapping\n"])
def test_bad_yaml_fails_before_model_loading(training_run: SimpleNamespace, content: str) -> None:
    training_run.config.write_text(content, encoding="utf-8")
    with pytest.raises(SystemExit) as error:
        train.main()
    assert error.value.code == 2
    training_run.constructors.assert_not_called()


def test_absolute_root_class_mapping_and_validation_alias_are_normalized(
    training_run: SimpleNamespace,
) -> None:
    config = yaml.safe_load(training_run.config.read_text(encoding="utf-8"))
    config["path"] = str(training_run.dataset)
    config["names"] = dict(enumerate(train.CLASSES))
    config["validation"] = config.pop("val")
    config["download"] = "must not run"
    training_run.config.write_text(yaml.safe_dump(config), encoding="utf-8")
    assert train.main() == 0
    for _, _, snapshot in training_run.calls:
        assert snapshot["names"] == train.CLASSES
        assert snapshot["val"] == str((training_run.dataset / "train/images").resolve())
        assert "validation" not in snapshot
        assert "download" not in snapshot
