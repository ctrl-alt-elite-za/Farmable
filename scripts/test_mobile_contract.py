"""Run Flutter's demo API contract suite against disposable loopback storage.

Run with ``uv run python scripts/test_mobile_contract.py`` on Linux/macOS.
The inherited listening socket reserves an ephemeral port until Uvicorn owns it.
No developer database or already-running server is used.
"""

import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from urllib.error import URLError
from urllib.request import urlopen

ROOT = Path(__file__).resolve().parents[1]


def main() -> int:
    flutter = shutil.which("flutter")
    if flutter is None:
        raise RuntimeError("Flutter must be installed to run the contract suite")
    with tempfile.TemporaryDirectory(prefix="farmable-mobile-contract-") as directory:
        env = {**os.environ, "FARMABLE_DEMO_DB": str(Path(directory) / "state.sqlite3")}
        subprocess.run(  # noqa: S603 - fixed module and arguments, no shell
            [sys.executable, "-m", "farmable_backend.demo_api.init"],
            cwd=ROOT,
            env=env,
            check=True,
            timeout=30,
        )
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            listener.listen()
            base_url = f"http://127.0.0.1:{listener.getsockname()[1]}"
            server = subprocess.Popen(  # noqa: S603 - fixed module and inherited socket
                [
                    sys.executable,
                    "-m",
                    "uvicorn",
                    "farmable_backend.demo_api.app:app",
                    "--fd",
                    str(listener.fileno()),
                    "--no-access-log",
                ],
                cwd=ROOT,
                env=env,
                pass_fds=(listener.fileno(),),
            )
            try:
                deadline = time.monotonic() + 30
                while True:
                    if server.poll() is not None:
                        raise RuntimeError("Demo API exited before becoming ready")
                    try:
                        with urlopen(  # noqa: S310 - URL is constructed from our loopback socket
                            base_url + "/health/live", timeout=1
                        ) as response:
                            if response.status == 200:
                                break
                    except (URLError, TimeoutError):
                        pass
                    if time.monotonic() >= deadline:
                        raise RuntimeError("Demo API did not become ready within 30 seconds")
                    time.sleep(0.1)
                return subprocess.run(  # noqa: S603 - installed Flutter, fixed test target
                    [
                        flutter,
                        "test",
                        "--no-pub",
                        "--reporter=expanded",
                        f"--dart-define=DEMO_API_URL={base_url}",
                        "test/demo_api_contract_test.dart",
                    ],
                    cwd=ROOT / "apps/mobile",
                    check=False,
                    timeout=300,
                ).returncode
            finally:
                server.terminate()
                try:
                    server.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    server.kill()
                    server.wait(timeout=10)


if __name__ == "__main__":
    raise SystemExit(main())
