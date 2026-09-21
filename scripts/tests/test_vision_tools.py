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

from vision import export  # noqa: E402
from vision.benchmark import (  # noqa: E402
    MIN_WARM_SAMPLES,
    build_report,
    percentile,
    read_samples,
    validate_report,
)
from vision.check_split import count_crop_images, split_sessions, validate_labels  # noqa: E402
from vision.eval_weights import fit_range, load_measurements  # noqa: E402
from vision.release import select_release, validate_fixture_report  # noqa: E402
from vision.train import report_for  # noqa: E402

# Keys accepted by the pinned Ultralytics cfg/default.yaml; anything else raises
# SyntaxError at export.
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
    Path(export.DEFAULT_MODEL).write_bytes(b"source-weights")
    monkeypatch.setattr(sys, "argv", ["export.py", *args])
    return export.main()


def release_inputs() -> tuple[dict, dict, dict, dict]:
    def report(platform: str, digest: str, size: int) -> dict:
        return build_report(
            model_version="demo1",
            artifact_sha256=digest,
            platform=platform,
            device=f"{platform} fixture",
            os_version="17",
            runtime="test runtime",
            precision="fp16",
            input_size=640,
            artifact_bytes=size,
            cold_load_ms=1,
            first_inference_ms=1,
            warm_sample_ms=[1, 2] * 10,
            warmup_iterations=1,
            peak_memory_mb=1,
        )

    labels = {
        "cabbage": "cabbage plant",
        "tomato": "tomato plant",
        "spinach": "spinach plant",
    }
    fixture_set: list[dict[str, object]] = [
        {
            "fixture_id": f"{crop}-{index}",
            "fixture_sha256": hashlib.sha256(f"{crop}-{index}".encode()).hexdigest(),
            "expected_crop": crop,
        }
        for crop in labels
        for index in (1, 2)
    ]
    fixture_set.extend(
        {
            "fixture_id": f"negative-{index}",
            "fixture_sha256": hashlib.sha256(f"negative-{index}".encode()).hexdigest(),
            "expected_crop": None,
        }
        for index in (1, 2)
    )
    results: list[dict[str, object]] = []
    for fixture in fixture_set:
        expected_crop = fixture["expected_crop"]
        assert expected_crop is None or isinstance(expected_crop, str)
        results.append(
            {
                "fixture_id": fixture["fixture_id"],
                "detected": expected_crop is not None,
                "raw_label": labels[expected_crop] if expected_crop is not None else None,
                "confidence": 0.9 if expected_crop is not None else None,
            }
        )
    fixtures = {
        "schema_version": 1,
        "model_version": "demo1",
        "fixture_set": fixture_set,
        "runs": {
            "ios": {
                "artifact_sha256": "a" * 64,
                "results": [dict(result) for result in results],
            },
            "android": {
                "artifact_sha256": "b" * 64,
                "results": [dict(result) for result in results],
            },
        },
    }
    manifest = {
        "version": "demo1",
        "measured": False,
        "source_model": export.DEFAULT_MODEL,
        "source_revision": export.DEFAULT_SOURCE_REVISION,
        "source_url": export.DEFAULT_SOURCE_URL,
        "source_sha256": "c" * 64,
        "license": export.DEFAULT_LICENSE,
        "classes": export.PROMPTS,
        "input_size": 640,
        "precision": "fp16",
        "artifacts": {
            "coreml": {"sha256": "a" * 64, "bytes": 10},
            "tflite": {"sha256": "b" * 64, "bytes": 20},
        },
    }
    return manifest, report("ios", "a" * 64, 10), report("android", "b" * 64, 20), fixtures


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
    assert manifest["source_revision"].startswith("Ultralytics assets release v8.4.0")
    assert export.ULTRALYTICS_EXPORTER_REVISION in manifest["source_revision"]
    assert manifest["license"].startswith("AGPL-3.0-only")
    assert manifest["source_sha256"] == hashlib.sha256(b"source-weights").hexdigest()
    assert manifest["classes"] == export.PROMPTS
    assert set(manifest["artifacts"]) == {"coreml", "tflite"}
    assert all(len(item["sha256"]) == 64 for item in manifest["artifacts"].values())
    assert all(item["bytes"] > 0 for item in manifest["artifacts"].values())
    assert Path("out/demo1.mlpackage/Manifest.json").is_file()
    assert Path("out/demo1.tflite").is_file()
    expected = hashlib.sha256(b"tflite").hexdigest()
    assert manifest["artifacts"]["tflite"]["sha256"] == expected


def test_benchmark_report_computes_warm_percentiles_and_requires_physical_device() -> None:
    report = build_report(
        model_version="demo1",
        artifact_sha256="a" * 64,
        platform="ios",
        device="iPhone fixture",
        os_version="17.0",
        runtime="Core ML",
        precision="fp16",
        input_size=640,
        artifact_bytes=123,
        cold_load_ms=12.0,
        first_inference_ms=4.0,
        warm_sample_ms=[10.0, 20.0, 30.0, 40.0] * 5,
        warmup_iterations=10,
        peak_memory_mb=50.0,
    )
    assert report["warm_samples"] == 20
    assert report["warm_p50_ms"] == 25.0
    assert report["warm_p95_ms"] == 40.0
    invalid = dict(report, measurement_source="desktop")
    with pytest.raises(ValueError, match="physical_device"):
        validate_report(invalid)


def test_benchmark_rejects_too_few_or_non_numeric_warm_samples(tmp_path: Path) -> None:
    with pytest.raises(ValueError, match="at least 20"):
        build_report(
            model_version="demo1",
            artifact_sha256="a" * 64,
            platform="ios",
            device="iPhone fixture",
            os_version="17",
            runtime="Core ML",
            precision="fp16",
            input_size=640,
            artifact_bytes=10,
            cold_load_ms=1,
            first_inference_ms=1,
            warm_sample_ms=[1] * 19,
            warmup_iterations=1,
            peak_memory_mb=1,
        )
    samples = tmp_path / "samples.json"
    samples.write_text('[1, true, "2"]', encoding="utf-8")
    with pytest.raises(ValueError, match="JSON number"):
        read_samples(samples)


def test_benchmark_requires_a_timezone_aware_creation_timestamp() -> None:
    report = release_inputs()[1]
    report.pop("created_at")
    with pytest.raises(ValueError, match="created_at"):
        validate_report(report)
    report["created_at"] = "2026-09-21T12:00:00"
    with pytest.raises(ValueError, match="timezone-aware"):
        validate_report(report)


def test_release_selection_requires_both_reports_and_usable_fixture_results() -> None:
    manifest, ios, android, fixtures = release_inputs()
    selected = select_release(
        manifest,
        ios,
        android,
        fixtures,
        accepted_licenses={export.DEFAULT_LICENSE},
        ios_report_sha256="d" * 64,
        android_report_sha256="e" * 64,
        fixture_report_sha256="f" * 64,
    )
    assert selected["measured"] is True
    assert selected["evidence_complete"] is True
    assert "selected_for_demo" not in selected
    assert selected["benchmarks"]["ios"] == {
        "path": "reports/ios.json",
        "sha256": "d" * 64,
    }
    assert selected["fixture_report"]["sha256"] == "f" * 64
    assert selected["fixture_report"]["schema_version"] == 1
    assert manifest["measured"] is False
    assert validate_fixture_report(fixtures)["schema_version"] == 1


def test_release_fails_closed_without_an_explicitly_accepted_license() -> None:
    manifest, ios, android, fixtures = release_inputs()
    with pytest.raises(ValueError, match="accepted license"):
        select_release(manifest, ios, android, fixtures)


def test_release_rejects_low_confidence_fixture_evidence() -> None:
    manifest, ios, android, fixtures = release_inputs()
    fixtures["runs"]["ios"]["results"][0]["confidence"] = 0.49
    with pytest.raises(ValueError, match="confidence"):
        select_release(
            manifest,
            ios,
            android,
            fixtures,
            accepted_licenses={export.DEFAULT_LICENSE},
        )


def test_fixture_report_rejects_non_string_labels_cleanly() -> None:
    fixtures = release_inputs()[3]
    fixtures["runs"]["ios"]["results"][0]["raw_label"] = ["cabbage plant"]
    with pytest.raises(ValueError, match="configured raw_label"):
        validate_fixture_report(fixtures)


def test_release_derives_and_rejects_negative_false_positives() -> None:
    manifest, ios, android, fixtures = release_inputs()
    negative = next(
        result
        for result in fixtures["runs"]["android"]["results"]
        if result["fixture_id"] == "negative-1"
    )
    negative.update(detected=True, raw_label="tomato fruit", confidence=0.9)
    with pytest.raises(ValueError, match="negative false positives"):
        select_release(
            manifest,
            ios,
            android,
            fixtures,
            accepted_licenses={export.DEFAULT_LICENSE},
        )


def test_fixture_report_requires_hashed_positive_and_negative_fixed_set() -> None:
    fixtures = release_inputs()[3]
    fixtures["fixture_set"] = [
        fixture for fixture in fixtures["fixture_set"] if fixture["expected_crop"] is not None
    ]
    kept_ids = {fixture["fixture_id"] for fixture in fixtures["fixture_set"]}
    for run in fixtures["runs"].values():
        run["results"] = [result for result in run["results"] if result["fixture_id"] in kept_ids]
    with pytest.raises(ValueError, match="negative fixtures"):
        validate_fixture_report(fixtures)


def test_fixture_report_rejects_duplicate_fixture_content() -> None:
    fixtures = release_inputs()[3]
    fixtures["fixture_set"][1]["fixture_sha256"] = fixtures["fixture_set"][0]["fixture_sha256"]
    with pytest.raises(ValueError, match="fixture_sha256 values must be unique"):
        validate_fixture_report(fixtures)


def test_release_binds_each_fixture_run_to_its_platform_artifact() -> None:
    manifest, ios, android, fixtures = release_inputs()
    fixtures["runs"]["android"]["artifact_sha256"] = "a" * 64
    with pytest.raises(ValueError, match="android fixture artifact hash"):
        select_release(
            manifest,
            ios,
            android,
            fixtures,
            accepted_licenses={export.DEFAULT_LICENSE},
        )


def test_release_requires_evidence_report_digests() -> None:
    manifest, ios, android, fixtures = release_inputs()
    with pytest.raises(ValueError, match="ios_report_sha256"):
        select_release(
            manifest,
            ios,
            android,
            fixtures,
            accepted_licenses={export.DEFAULT_LICENSE},
        )


def test_percentile_interpolation_and_minimum_sample_boundary() -> None:
    assert percentile([0, 10], 95) == 9.5
    report = release_inputs()[1]
    assert report["warm_samples"] == MIN_WARM_SAMPLES
    assert validate_report(report) is report


def test_export_rejects_unsafe_version_before_loading_model(
    fake_yoloe: type[FakeYOLOE],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as error:
        run_export(monkeypatch, "--version", "../escape", "--output-dir", "out")
    assert error.value.code == 2
    assert "version" in capsys.readouterr().err
    assert not fake_yoloe.instances


def test_int8_export_rejects_missing_calibration_path_before_loading_model(
    fake_yoloe: type[FakeYOLOE],
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
) -> None:
    with pytest.raises(SystemExit) as error:
        run_export(
            monkeypatch,
            "--version",
            "demo1",
            "--int8",
            "--data",
            "missing.yaml",
        )
    assert error.value.code == 2
    assert "calibration" in capsys.readouterr().err
    assert not fake_yoloe.instances


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


def test_package_digest_is_independent_of_package_directory_name(tmp_path: Path) -> None:
    first = tmp_path / "first.mlpackage"
    second = tmp_path / "renamed.mlpackage"
    for package in (first, second):
        nested = package / "Data"
        nested.mkdir(parents=True)
        (package / "Manifest.json").write_text('{"version": 1}', encoding="utf-8")
        (nested / "weights.bin").write_bytes(b"weights")
    assert export.sha256(first) == export.sha256(second)


def test_export_failure_leaves_no_partial_version(
    fake_yoloe: type[FakeYOLOE], monkeypatch: pytest.MonkeyPatch
) -> None:
    original_export = FakeYOLOE.export

    def fail_android(self: FakeYOLOE, **options: object) -> str:
        if options["format"] == "tflite":
            raise RuntimeError("simulated TFLite exporter failure")
        return original_export(self, **options)

    monkeypatch.setattr(FakeYOLOE, "export", fail_android)
    with pytest.raises(RuntimeError, match="simulated"):
        run_export(monkeypatch, "--version", "demo1", "--output-dir", "out")
    assert list(Path("out").iterdir()) == []


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
    manifest.write_text(
        "image,session_id,crop\nmorning_1.jpg,s1,cabbage\nmorning_2.jpg,s1,tomato\n",
        encoding="utf-8",
    )
    train_sessions, test_sessions = split_sessions(train, test, manifest)
    assert train_sessions & test_sessions == {"s1"}


def test_weight_fit_requires_twenty_real_measurements(tmp_path: Path) -> None:
    path = tmp_path / "cabbage.csv"
    path.write_text("diameter_cm,weight_g,date\n10,500,2026-09-17\n", encoding="utf-8")
    with pytest.raises(ValueError, match="at least 20"):
        load_measurements(path)


def test_weight_fit_requires_measurement_dates(tmp_path: Path) -> None:
    path = tmp_path / "cabbage.csv"
    path.write_text("diameter_cm,weight_g\n10,500\n", encoding="utf-8")
    with pytest.raises(ValueError, match="date"):
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


def test_crop_counts_are_derived_from_manifest_and_images(tmp_path: Path) -> None:
    images = tmp_path / "train" / "images"
    images.mkdir(parents=True)
    (images / "frame.jpg").touch()
    manifest = tmp_path / "sessions.csv"
    manifest.write_text("image,session_id,crop\nframe.jpg,s1,cabbage\n", encoding="utf-8")
    assert count_crop_images(images, tmp_path / "test", manifest)["cabbage"] == 1


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
