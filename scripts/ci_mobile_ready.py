"""Detect the Flutter client before running mobile build checks."""

import json
import os
from pathlib import Path


def main() -> None:
    ready = Path("apps/mobile/pubspec.yaml").is_file()
    ready = ready and Path("apps/mobile/lib/main.dart").is_file()
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
        message = "Mobile E2E NOT VERIFIED: Flutter client or Maestro flows are unavailable.\n"
        print(message)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
                stream.write(message)


if __name__ == "__main__":
    main()
