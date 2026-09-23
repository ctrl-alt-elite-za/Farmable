"""Opt-in import-job notification; never load this credential into the API client."""

import json
import re
import time

import httpx
from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict

from farmable_backend.forecasts import ImportResult, locked_state

CHECKS = frozenset(
    {
        "schema",
        "run_id_mismatch",
        "crop_month_coverage",
        "prices_positive",
        "quantiles_ordered",
        "data_mode_mismatch",
        "method_kind_mismatch",
        "duplicate_sources",
        "as_of_regression",
        "p50_jump",
        "as_of_future",
        "run_id_conflict",
        "invalid_run_id",
        "unsafe_artifact",
        "artifact_missing",
        "bundle_too_large",
        "import_failed",
    }
)
MAX_PAGES = 10
MAX_RESPONSE_BYTES = 1_048_576


class NotificationSettings(BaseSettings):
    model_config = SettingsConfigDict(
        env_prefix="FORECAST_GITHUB_",
        extra="ignore",
        env_ignore_empty=True,
        hide_input_in_errors=True,
    )
    enabled: bool = False
    repository: str | None = Field(
        default=None, pattern=r"^[A-Za-z0-9_-]{1,100}/[A-Za-z0-9_.-]{1,100}$"
    )
    token: SecretStr | None = Field(default=None, repr=False)


def issue_content(result: ImportResult) -> tuple[str, str]:
    if (
        re.fullmatch(r"[a-z0-9][a-z0-9_-]{0,63}", result.run_id) is None
        or not result.failed_checks
        or not set(result.failed_checks) <= CHECKS
    ):
        raise ValueError("unsafe_notification")
    # One issue per run, regardless of changing failure details. Never copy data,
    # paths, exception text or provider response bodies into GitHub.
    title = f"Forecast import failed: {result.run_id}"
    body = (
        f"<!-- forecast-import:{result.run_id} -->\nRun: `{result.run_id}`\n\nFailed checks:\n"
        + "\n".join(f"- `{check}`" for check in sorted(set(result.failed_checks)))
    )
    return title, body


class GitHubFailureNotifier:
    def __init__(
        self,
        sessions,
        settings: NotificationSettings,
        *,
        transport: httpx.BaseTransport | None = None,
    ):
        self.sessions = sessions
        self.settings = settings
        self.transport = transport

    def __call__(self, result: ImportResult) -> None:
        title, body = issue_content(result)
        config = self.settings
        if not config.enabled:
            return
        if not config.repository or not config.token or not config.token.get_secret_value().strip():
            raise ValueError("notification_not_configured")
        path = f"https://api.github.com/repos/{config.repository}/issues"
        headers = {
            "Authorization": f"Bearer {config.token.get_secret_value()}",
            "Accept": "application/vnd.github+json",
            "X-GitHub-Api-Version": "2022-11-28",
        }
        # Serialize cooperating import jobs on the existing singleton. Ordinary
        # outlook reads do not acquire this lock. Release it on every failure.
        # This runs AFTER the import transaction committed, never around activation.
        with self.sessions.begin() as session:
            locked_state(session)
            deadline = time.monotonic() + 20
            with httpx.Client(
                headers=headers,
                timeout=5,
                follow_redirects=False,
                trust_env=False,
                transport=self.transport,
            ) as client:
                for page in range(1, MAX_PAGES + 1):
                    issues = self._request(
                        client,
                        "GET",
                        path,
                        deadline,
                        params={
                            "state": "all",
                            "per_page": 100,
                            "page": page,
                            "sort": "created",
                            "direction": "asc",
                        },
                    )
                    if not isinstance(issues, list) or any(
                        not isinstance(item, dict) for item in issues
                    ):
                        raise ValueError("notification_response_invalid")
                    # Include closed issues: closing a report is not a request to
                    # reopen it on every deploy. PRs cannot suppress a real issue.
                    if any(
                        "pull_request" not in item
                        and isinstance(item.get("body"), str)
                        and f"<!-- forecast-import:{result.run_id} -->" in item["body"]
                        for item in issues
                    ):
                        return
                    if len(issues) < 100:
                        break
                else:
                    # Incomplete lookup must not result in a duplicate issue.
                    raise ValueError("notification_scan_limit")
                created = self._request(
                    client, "POST", path, deadline, json={"title": title, "body": body}
                )
                if (
                    not isinstance(created, dict)
                    or type(created.get("number")) is not int
                    or created["number"] < 1
                ):
                    raise ValueError("notification_response_invalid")

    @staticmethod
    def _request(client, method, path, deadline, **kwargs):
        if time.monotonic() >= deadline:
            raise TimeoutError("notification_timeout")
        # Do not retry POST: a timeout may mean GitHub created the issue already.
        # A later import first looks it up again. Never follow a redirect with a token.
        with client.stream(method, path, **kwargs) as response:
            response.raise_for_status()
            content = bytearray()
            for chunk in response.iter_bytes():
                content.extend(chunk)
                if len(content) > MAX_RESPONSE_BYTES or time.monotonic() >= deadline:
                    raise ValueError("notification_response_limit")
            return json.loads(content)
