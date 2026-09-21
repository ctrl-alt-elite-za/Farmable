"""Do not fabricate a passing mobile E2E result before the app can actually be driven.

The mobile E2E job is only meaningful once three things exist together: a
Flutter app that builds, the Maestro flows that drive it, and screens for those
flows to reach. Until then this reports the check as a *prerequisite*, not a
pass, so a green tick never implies the app was exercised on a device.
"""

import json
import os
from pathlib import Path

APP = Path("apps/mobile")


def _is_flutter_app() -> bool:
    """A Flutter app, not merely a directory someone created."""
    pubspec = APP / "pubspec.yaml"
    if not pubspec.is_file():
        return False
    text = pubspec.read_text(encoding="utf-8")
    # `sdk: flutter` under dependencies is what distinguishes a Flutter app
    # from a plain Dart package.
    return "sdk: flutter" in text and (APP / "lib" / "main.dart").is_file()


def main() -> None:
    ready = _is_flutter_app()
    ready = ready and (APP / "android").is_dir()
    ready = ready and any(Path("e2e/mobile").glob("*.yaml"))

    if os.environ.get("GITHUB_OUTPUT"):
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
            stream.write(f"ready={str(ready).lower()}\n")

    if not ready:
        Path(".ci-reports").mkdir(exist_ok=True)
        Path(".ci-reports/e2e-mobile.json").write_text(
            json.dumps(
                {
                    "check": "e2e-mobile",
                    "failed": False,
                    "diagnostics": ["prerequisite"],
                    "quarantined": [],
                }
            ),
            encoding="utf-8",
        )
        message = "Mobile E2E NOT VERIFIED: waiting for the Flutter app and Maestro flows.\n"
        print(message)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
                stream.write(message)


if __name__ == "__main__":
    main()
