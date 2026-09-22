"""Explicit forecast import/rollback commands; import failures do not fail deployment."""

import argparse
import re
from collections.abc import Callable
from pathlib import Path

from farmable_backend.config import Settings
from farmable_backend.database import Database
from farmable_backend.forecast_contract import Mode
from farmable_backend.forecasts import MAX_BUNDLE_BYTES, ImportResult, activate, import_bundle

RUN_PATTERN = r"[a-z0-9][a-z0-9_-]{0,63}"


def warning(result: ImportResult) -> None:
    # Only validated IDs and fixed check names, never artifact contents/exception text.
    print(f"forecast-warning run={result.run_id} checks={','.join(result.failed_checks)}")


def import_latest(
    sessions,
    root: Path,
    mode: Mode,
    notify: Callable[[ImportResult], None] = warning,
) -> list[ImportResult]:
    if mode == "disabled":
        return []  # Disabled deployments must not consume immutable run IDs.
    if not root.exists():
        return []
    if not root.is_dir():
        raise ValueError("invalid_results_directory")
    folders = []
    # Bound discovery too; no unbounded walk or recursion into arbitrary artifacts.
    for entry in root.iterdir():
        if entry.is_dir():
            folders.append(entry)
            if len(folders) > 256:
                raise ValueError("too_many_runs")
    results = []
    for folder in sorted(folders):
        if re.fullmatch(RUN_PATTERN, folder.name) is None:
            result = ImportResult("invalid-run-id", "rejected", ("invalid_run_id",))
        else:
            artifact = folder / "forecast.json"
            try:
                if folder.is_symlink() or artifact.is_symlink():
                    raise ValueError("unsafe_artifact")
                if (
                    folder.resolve().parent != root.resolve()
                    or artifact.resolve().parent != folder.resolve()
                ):
                    raise ValueError("unsafe_artifact")
                if not artifact.is_file():
                    raise ValueError("artifact_missing")
                with artifact.open("rb") as stream:
                    raw = stream.read(MAX_BUNDLE_BYTES + 1)
                if len(raw) > MAX_BUNDLE_BYTES:
                    raise ValueError("bundle_too_large")
                result = import_bundle(sessions, folder.name, raw, mode)
            except ValueError as exc:
                code = str(exc)
                if code not in {"unsafe_artifact", "artifact_missing", "bundle_too_large"}:
                    code = "import_failed"
                result = ImportResult(folder.name, "rejected", (code,))
            except Exception:
                result = ImportResult(folder.name, "rejected", ("import_failed",))
        results.append(result)
        if result.failed_checks:
            try:
                notify(result)
            except Exception:
                warning(ImportResult(result.run_id, "rejected", ("notification_failed",)))
    return results


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    importer = commands.add_parser("import-latest")
    importer.add_argument("--root", type=Path, default=Path("ml/forecast/results"))
    rollback = commands.add_parser("activate")
    rollback.add_argument("--run", required=True)
    args = parser.parse_args(argv)
    database = None
    try:
        config = Settings()
        if args.command == "import-latest" and config.forecast_data_mode == "disabled":
            print("forecast-import disabled; no changes")
            return 0
        database = Database(config)
        if args.command == "import-latest":
            results = import_latest(database.sessions, args.root, config.forecast_data_mode)
            failed = sum(bool(result.failed_checks) for result in results)
            print(f"forecast-import examined={len(results)} failed={failed}")
        else:
            if re.fullmatch(RUN_PATTERN, args.run) is None:
                raise ValueError("invalid_run_id")
            activate(database.sessions, args.run, config.forecast_data_mode)
            print(f"forecast-activate run={args.run}")
        return 0
    except Exception:
        warning(ImportResult("command", "rejected", ("command_failed",)))
        return 0 if args.command == "import-latest" else 1
    finally:
        if database is not None:
            try:
                database.close()
            except Exception:
                warning(ImportResult("command", "rejected", ("cleanup_failed",)))


if __name__ == "__main__":
    raise SystemExit(main())
