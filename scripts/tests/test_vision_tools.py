import hashlib
import json
import shutil
import subprocess
import sys
from pathlib import Path
from types import SimpleNamespace

import pytest

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "apps/ml-service"))

from vision import export
from vision.check_split import split_sessions, validate_labels
from vision.eval_weights import fit_range, load_measurements
from vision.train import report_for

# Keys accepted by ultralytics==8.4.0 cfg/default.yaml; anything else raises SyntaxError at export.
ULTRALYTICS_EXPORT_KEYS = {"format", "imgsz", "half", "int8", "data", "nms", "batch", "dynamic"}


class FakeYOLOE:
    instances: list["FakeYOLOE"] = []

    def __init__(self, weights: str) -> None:
        self.weights = weights
        self.exports: list[dict[str, object]] = []
        FakeYOLOE.instances.append(self)

    def set_classes(self, classes: list[str]) -> None:
        self.classes = list(classes)

    def export(self, **options: object) -> str:
        self.exports.append(options)
        build = Path(str(self.weights)).parent
        if options["format"] == "coreml":
            package = build / "build.mlpackage"
            package.mkdir(exist_ok=True)
            (package / "Manifest.json").write_text("{}", encoding="utf-8")
            return str(package)
        model = build / "build_float16.tflite"
        model.write_bytes(b"tflite")
        return str(model)


@pytest.fixture
def fake_yoloe(tmp_path: Path, monkeypatch: pytest.MonkeyPatch) -> type[FakeYOLOE]:
    FakeYOLOE.instances = []
    monkeypatch.setitem(sys.modules, "ultralytics", SimpleNamespace(YOLOE=FakeYOLOE))
    monkeypatch.chdir(tmp_path)
    return FakeYOLOE


def run_export(monkeypatch: pytest.MonkeyPatch, *args: str) -> int:
    monkeypatch.setattr(sys, "argv", ["export.py", "--model", "weights.pt", *args])
    return export.main()


def test_export_passes_only_arguments_ultralytics_accepts(
    fake_yoloe: type[FakeYOLOE], monkeypatch: pytest.MonkeyPatch
) -> None:
    assert run_export(monkeypatch, "--version", "demo1", "--output-dir", "out") == 0
    (model,) = fake_yoloe.instances
    assert [options["format"] for options in model.exports] == ["coreml", "tflite"]
    for options in model.exports:
        assert set(options) <= ULTRALYTICS_EXPORT_KEYS
        assert options["half"] is True


def test_export_manifest_marks_demo_artifacts_unmeasured_with_hashes(
    fake_yoloe: type[FakeYOLOE], monkeypatch: pytest.MonkeyPatch
) -> None:
    run_export(monkeypatch, "--version", "demo1", "--output-dir", "out")
    manifest = json.loads(Path("out/demo1.json").read_text(encoding="utf-8"))
    assert manifest["measured"] is False
    assert manifest["precision"] == "fp16"
    assert set(manifest["artifacts"]) == {"coreml", "tflite"}
    assert all(len(item["sha256"]) == 64 for item in manifest["artifacts"].values())
    assert Path("out/demo1.mlpackage/Manifest.json").is_file()
    assert Path("out/demo1.tflite").is_file()
    expected = hashlib.sha256(b"tflite").hexdigest()
    assert manifest["artifacts"]["tflite"]["sha256"] == expected


def test_int8_export_requires_crop_calibration_data(
    fake_yoloe: type[FakeYOLOE],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as error:
        run_export(monkeypatch, "--version", "demo1", "--int8")
    assert error.value.code == 2
    assert "calibration" in capsys.readouterr().err
    assert not fake_yoloe.instances


def test_export_refuses_to_overwrite_an_existing_version(
    fake_yoloe: type[FakeYOLOE], monkeypatch: pytest.MonkeyPatch
) -> None:
    Path("out/demo1.tflite").parent.mkdir()
    Path("out/demo1.tflite").write_bytes(b"old")
    with pytest.raises(SystemExit) as error:
        run_export(monkeypatch, "--version", "demo1", "--output-dir", "out")
    assert error.value.code == 2
    assert not fake_yoloe.instances


@pytest.mark.parametrize(
    ("path", "ignored"),
    [
        ("apps/ml-service/vision/runs/v1/train_batch0.jpg", True),
        ("apps/ml-service/vision/reports/v1/val_batch0_pred.jpg", True),
        ("apps/ml-service/vision/reports/v1/results.csv", True),
        ("apps/ml-service/vision/models/v1.tflite", True),
        ("apps/ml-service/vision/reports/v1.json", False),
    ],
)
def test_private_training_outputs_are_git_ignored(path: str, ignored: bool) -> None:
    git = shutil.which("git")
    assert git
    result = subprocess.run(  # noqa: S603
        [git, "check-ignore", "--no-index", "-q", path], cwd=ROOT, check=False
    )
    assert (result.returncode == 0) is ignored


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
    report = report_for(
        "v1",
        42,
        10,
        {},
        ["train-a"],
        ["test-a"],
        crop_counts={"cabbage": 300, "tomato": 300, "spinach": 300},
    )
    assert set(report["classes"]) == {"plant", "crop_head_or_fruit", "check_suggested"}
    assert set(report["classes"]["plant"]) == {"precision", "recall", "map50"}
    assert report["train_sessions"] == ["train-a"]
    assert report["test_sessions"] == ["test-a"]
    assert report["crops"]["spinach"]["images"] == 300
