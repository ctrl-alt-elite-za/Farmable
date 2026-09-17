"""Do not fabricate a passing mobile test before issue #4 supplies the app and flows."""

import json
import os
from pathlib import Path


def main() -> None:
    package = json.loads(Path("apps/mobile/package.json").read_text(encoding="utf-8"))
    ready = "expo" in package.get("dependencies", {})
    ready = ready and any(
        Path("apps/mobile", name).is_file()
        for name in ("app.json", "app.config.js", "app.config.ts")
    )
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
        message = "Mobile E2E NOT VERIFIED: waiting for #4's Expo app and Maestro flows.\n"
        print(message)
        if os.environ.get("GITHUB_STEP_SUMMARY"):
            with Path(os.environ["GITHUB_STEP_SUMMARY"]).open("a", encoding="utf-8") as stream:
                stream.write(message)


if __name__ == "__main__":
    main()
