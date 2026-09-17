"""Lint ONLY pending Alembic-generated upgrades. Never execute SQL or connect to a database."""

import ast
import io
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

from alembic import command
from alembic.config import Config


def git(*args: str) -> str:
    executable = shutil.which("git")
    if executable is None:
        raise RuntimeError("Git is required")
    return subprocess.run(  # noqa: S603
        [executable, *args],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def base_head(base: str) -> str:
    files = git("ls-tree", "-r", "--name-only", base, "--", "migrations/versions").splitlines()
    revisions: set[str] = set()
    parents: set[str | None] = set()
    for filename in files:
        if not filename.endswith(".py"):
            continue
        tree = ast.parse(git("show", f"{base}:{filename}"))
        values = {}
        for node in tree.body:
            if isinstance(node, ast.Assign):
                for target in node.targets:
                    if isinstance(target, ast.Name) and target.id in {"revision", "down_revision"}:
                        values[target.id] = ast.literal_eval(node.value)
            elif isinstance(node, ast.AnnAssign) and isinstance(node.target, ast.Name):
                if node.target.id in {"revision", "down_revision"} and node.value is not None:
                    values[node.target.id] = ast.literal_eval(node.value)
        if "revision" in values:
            revisions.add(values["revision"])
            parent = values.get("down_revision")
            parents.update(parent if isinstance(parent, tuple | list) else [parent])
    heads = revisions - parents
    if len(heads) != 1:
        raise ValueError("Base migrations must have exactly one head")
    return heads.pop()


def main() -> int:
    base = os.environ.get("CI_BASE", "origin/main")
    changes = git("diff", "--name-status", base + "...HEAD", "--", "migrations/versions")
    if any(line and not line.startswith("A\t") for line in changes.splitlines()):
        print("migration-danger: existing migrations are immutable; add a new revision")
        return 1
    stream = io.StringIO()
    config = Config("alembic.ini", output_buffer=stream)
    command.upgrade(config, base_head(base) + ":heads", sql=True)
    sql = stream.getvalue()
    report_dir = Path(".ci-reports")
    report_dir.mkdir(exist_ok=True)
    sql_path = report_dir / "migration.sql"
    sql_path.write_text(sql, encoding="utf-8")
    uvx = shutil.which("uvx")
    if uvx is None:
        raise RuntimeError("uvx is required")
    result = subprocess.run(  # noqa: S603
        [
            uvx,
            "--from",
            "squawk-cli==2.65.0",
            "squawk",
            "--pg-version=16",
            "--reporter=json",
            str(sql_path),
        ],
        capture_output=True,
        text=True,
        check=False,
        timeout=5 * 60,
    )
    if result.returncode == 0:
        print("Pending generated migration SQL is safe")
        return 0
    if result.returncode != 1:
        print("migration-danger: SQL linter failed; approval cannot bypass tool failure")
        return 1
    try:
        issues = json.loads(result.stdout)
        if not isinstance(issues, list) or not issues:
            raise ValueError("Invalid lint output")
        if any(not isinstance(item, dict) or item.get("level") != "Warning" for item in issues):
            raise ValueError("SQL parse failure")
    except ValueError:
        print("migration-danger: SQL parser/report failure cannot be label-bypassed")
        return 1
    print("migration-danger: " + result.stdout)
    if os.environ.get("CI_MIGRATION_APPROVED") == "true":
        print("Dangerous migration explicitly approved by maintainer label")
        return 0
    print("Require the migration-approved label before merging")
    return 1


if __name__ == "__main__":
    sys.exit(main())
