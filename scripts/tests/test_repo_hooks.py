"""Behavioral regressions for the repository's Bash hooks and setup recipe."""

import os
import shutil
import subprocess
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[2]


@pytest.fixture
def bash() -> str:
    # Native Windows tests can select Git Bash instead of the WSL launcher.
    executable = os.environ.get("FARMABLE_TEST_BASH") or shutil.which("bash")
    if executable is None:
        pytest.skip("Bash is required for repository hook tests")
    return executable


def run_bash(
    bash: str,
    directory: Path,
    script: str,
    *args: str,
    env: dict[str, str] | None = None,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(  # noqa: S603 - fixed test scripts; fixture data is passed as arguments
        [bash, "-c", script, "test", *args],
        cwd=directory,
        env={**os.environ, **(env or {})},
        capture_output=True,
        text=True,
        check=False,
    )


@pytest.mark.parametrize("partially_staged", [False, True])
def test_pre_commit_handles_leading_dash_filenames(
    tmp_path: Path, bash: str, partially_staged: bool
) -> None:
    result = run_bash(
        bash,
        tmp_path,
        """
set -e
git init -q
git config core.autocrlf false
printf 'original\n' > ./-sample.py
git add -- -sample.py
if [ "$2" = partial ]; then
  printf 'unstaged\n' >> ./-sample.py
fi
uv() {
  if [ ! -f .autofixed ]; then
    printf 'fixed\n' >> ./-sample.py
    touch .autofixed
    return 1
  fi
  return 0
}
export -f uv
status=0
bash "$1" || status=$?
git show ':-sample.py'
exit "$status"
""",
        (REPO / "scripts/hooks/pre-commit").as_posix(),
        "partial" if partially_staged else "full",
    )
    if partially_staged:
        assert result.returncode == 1
        assert "not fully staged" in result.stderr
        assert "fixed" not in result.stdout
        assert "unstaged" not in result.stdout
    else:
        assert result.returncode == 0, result.stderr
        assert "fixed" in result.stdout


@pytest.mark.parametrize(
    "changed_files,expected_scans",
    [
        ("apps/backend/a.py\nmigrations/b.py", 1),
        ("apps/backend/a.py", 1),
        ("migrations/b.py", 1),
        ("scripts/a.py", 0),
    ],
)
@pytest.mark.parametrize("sql_status", [0, 1])
def test_pre_push_scans_sql_once_and_preserves_failures(
    tmp_path: Path, bash: str, changed_files: str, expected_scans: int, sql_status: int
) -> None:
    scripts = tmp_path / "scripts"
    scripts.mkdir()
    for name, source in {
        "has-py-files.sh": "#!/usr/bin/env bash\nexit 0\n",
        "check-no-raw-sql.sh": (
            "#!/usr/bin/env bash\nprintf 'scan\\n' >> sql-scans.log\n" 'exit "$TASK_SQL_STATUS"\n'
        ),
    }.items():
        path = scripts / name
        path.write_text(source, encoding="utf-8")
        path.chmod(0o755)
    result = run_bash(
        bash,
        tmp_path,
        """
git() {
  case "$1" in
    merge-base) printf 'base\n' ;;
    diff) printf '%s\n' "$TASK_CHANGED_FILES" ;;
  esac
}
pnpm() { return 0; }
export -f git pnpm
bash "$1"
""",
        (REPO / "scripts/changed-scopes.sh").as_posix(),
        env={"TASK_CHANGED_FILES": changed_files, "TASK_SQL_STATUS": str(sql_status)},
    )
    log = tmp_path / "sql-scans.log"
    scans = log.read_text(encoding="utf-8").splitlines() if log.exists() else []
    assert len(scans) == expected_scans
    assert result.returncode == (sql_status if expected_scans else 0), result.stderr


@pytest.mark.parametrize("uv_status,pnpm_status", [(0, 0), (17, 0), (0, 23), (17, 23)])
def test_parallel_setup_reports_dependency_failures(
    tmp_path: Path, bash: str, uv_status: int, pnpm_status: int
) -> None:
    makefile = (REPO / "Makefile").read_text(encoding="utf-8")
    start = makefile.index("\t@set -e;")
    end = makefile.index("\n\t$(MAKE) hooks", start)
    recipe = makefile[start:end].removeprefix("\t@").replace("$$", "$")
    result = run_bash(
        bash,
        tmp_path,
        """
uv() { return "$TASK_UV_STATUS"; }
pnpm() { return "$TASK_PNPM_STATUS"; }
"""
        + recipe,
        env={"TASK_UV_STATUS": str(uv_status), "TASK_PNPM_STATUS": str(pnpm_status)},
    )
    assert result.returncode == (uv_status or pnpm_status)
    if uv_status:
        assert "uv sync failed" in result.stderr
    elif pnpm_status:
        assert "pnpm install failed" in result.stderr
