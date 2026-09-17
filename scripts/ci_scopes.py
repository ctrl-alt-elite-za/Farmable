"""Conservative changed-folder detection; workflows always start so checks cannot stay pending."""

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path


def scopes(paths: list[str]) -> dict[str, bool]:
    shared = any(
        path.startswith((".github/", "scripts/", "packages/", "migrations/", "e2e/", "infra/"))
        or "/" not in path
        and path not in {"README.md", "AGENTS.md", "LICENSE"}
        for path in paths
    )
    backend = shared or any(
        path.startswith(("apps/backend/", "apps/ml-service/")) for path in paths
    )
    mobile = shared or backend or any(path.startswith("apps/mobile/") for path in paths)
    assistant = any(
        path.startswith(
            (
                "backend/app/assistant/",
                "apps/backend/src/farmable_backend/assistant/",
                "e2e/evals/assistant/",
            )
        )
        for path in paths
    )
    return {"backend": backend, "mobile": mobile, "any": backend or mobile, "assistant": assistant}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--base", required=True)
    args = parser.parse_args()
    git = shutil.which("git")
    if git is None:
        raise RuntimeError("Git is required")
    result = subprocess.run(  # noqa: S603
        [git, "diff", "--no-renames", "--name-only", "-z", args.base + "...HEAD"],
        check=True,
        capture_output=True,
        text=True,
    )
    output = scopes([path for path in result.stdout.split("\0") if path])
    print(json.dumps(output))
    if os.environ.get("GITHUB_OUTPUT"):
        with Path(os.environ["GITHUB_OUTPUT"]).open("a", encoding="utf-8") as stream:
            stream.writelines(f"{key}={str(value).lower()}\n" for key, value in output.items())


if __name__ == "__main__":
    main()
