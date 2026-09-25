"""No real GitHub calls: exercise the actual notifier through HTTP transport fakes."""

import json
from types import SimpleNamespace

import httpx
import pytest
from farmable_backend import forecast_cli
from farmable_backend.forecast_notifications import (
    GitHubFailureNotifier,
    NotificationSettings,
    issue_content,
)
from farmable_backend.forecasts import ImportResult, import_bundle
from pydantic import SecretStr
from test_forecasts import bundle, get_outlook, raw

pytest_plugins = ("test_forecasts",)

FAILURE = ImportResult("invalid", "staged", ("prices_positive",))


def config():
    return NotificationSettings(
        enabled=True,
        repository="example/farmable",
        token=SecretStr("test-only-credential"),
    )


class FakeGitHub:
    def __init__(self):
        self.issues = []
        self.requests = []

    def __call__(self, request):
        self.requests.append(request)
        assert request.url.host == "api.github.com"
        assert request.url.path == "/repos/example/farmable/issues"
        assert request.headers["authorization"] == "Bearer test-only-credential"
        if request.method == "GET":
            assert request.url.params["state"] == "all"
            start = (int(request.url.params["page"]) - 1) * 100
            return httpx.Response(200, json=self.issues[start : start + 100])
        item = {"number": len(self.issues) + 1, **json.loads(request.content)}
        self.issues.append(item)
        return httpx.Response(201, json=item)


def test_invalid_import_opens_one_issue_and_preserves_active(forecasts, tmp_path):
    import_bundle(forecasts.sessions, "sample-v1", raw(bundle()), "sample")
    data = bundle("invalid")
    data["rows"][0]["p10"] = "-123456.789"
    folder = tmp_path / "invalid"
    folder.mkdir()
    (folder / "forecast.json").write_bytes(raw(data))
    github = FakeGitHub()
    notifier = GitHubFailureNotifier(
        forecasts.sessions, config(), transport=httpx.MockTransport(github)
    )
    for _ in range(2):
        result = forecast_cli.import_latest(forecasts.sessions, tmp_path, "sample", notifier)
        assert result == [FAILURE]
    assert len(github.issues) == 1
    assert github.issues[0]["body"] == (
        "<!-- forecast-import:invalid -->\nRun: `invalid`\n\nFailed checks:\n- `prices_positive`"
    )
    assert get_outlook(forecasts).json()["run_id"] == "sample-v1"


def test_pagination_closed_issues_and_pull_requests(forecasts):
    github = FakeGitHub()
    title, body = issue_content(FAILURE)
    github.issues = [{"title": "unrelated"}] * 100 + [
        {"title": "Renamed by maintainer", "body": body, "state": "closed"}
    ]
    notifier = GitHubFailureNotifier(
        forecasts.sessions, config(), transport=httpx.MockTransport(github)
    )
    notifier(FAILURE)
    assert [request.method for request in github.requests] == ["GET", "GET"]
    github.issues = [{"title": title, "body": body, "pull_request": {}}]
    notifier(FAILURE)
    assert github.requests[-1].method == "POST"


@pytest.mark.parametrize("status", [301, 401, 403, 429, 500])
def test_http_failure_never_posts_or_follows_redirect(forecasts, status):
    requests = []

    def failure(request):
        requests.append(request)
        return httpx.Response(
            status, headers={"location": "https://other.test"}, text="private-provider-error"
        )

    notifier = GitHubFailureNotifier(
        forecasts.sessions, config(), transport=httpx.MockTransport(failure)
    )
    with pytest.raises(httpx.HTTPStatusError):
        notifier(FAILURE)
    assert len(requests) == 1 and requests[0].method == "GET"


def test_ambiguous_post_is_not_retried_and_next_import_deduplicates(forecasts):
    github = FakeGitHub()

    def timeout_after_create(request):
        response = github(request)
        if request.method == "POST":
            raise httpx.ReadTimeout("private-token")
        return response

    notifier = GitHubFailureNotifier(
        forecasts.sessions, config(), transport=httpx.MockTransport(timeout_after_create)
    )
    with pytest.raises(httpx.ReadTimeout):
        notifier(FAILURE)
    notifier(FAILURE)
    assert len(github.issues) == 1
    assert sum(request.method == "POST" for request in github.requests) == 1


@pytest.mark.parametrize("response", ["malformed", "oversized", "full", "wrong-shape"])
def test_incomplete_or_invalid_lookup_never_creates(forecasts, response):
    requests = []

    def handler(request):
        requests.append(request)
        assert request.method == "GET"
        if response == "malformed":
            return httpx.Response(200, text="not json")
        if response == "oversized":
            return httpx.Response(200, content=b"x" * 1_048_577)
        return httpx.Response(200, json=[{}] * 100 if response == "full" else {})

    notifier = GitHubFailureNotifier(
        forecasts.sessions, config(), transport=httpx.MockTransport(handler)
    )
    with pytest.raises(ValueError):
        notifier(FAILURE)
    assert len(requests) == (10 if response == "full" else 1)


@pytest.mark.parametrize(
    "result",
    [
        ImportResult("bad\n@everyone", "staged", ("schema",)),
        ImportResult("invalid", "staged", ("private-data",)),
        ImportResult("valid", "active"),
    ],
)
def test_untrusted_notification_content_rejected(result):
    with pytest.raises(ValueError, match="unsafe_notification"):
        issue_content(result)


def test_cli_notification_failure_is_safe_and_import_continues(
    forecasts,
    tmp_path,
    monkeypatch,
    settings,
    capsys,
):
    (tmp_path / "invalid").mkdir()
    monkeypatch.setattr(
        forecast_cli,
        "DatabaseSettings",
        lambda: settings.model_copy(update={"forecast_data_mode": "sample"}),
    )
    monkeypatch.setattr(
        forecast_cli,
        "Database",
        lambda _: SimpleNamespace(sessions=forecasts.sessions, close=lambda: None),
    )
    monkeypatch.setattr(forecast_cli, "NotificationSettings", config)

    def broken(*args):
        raise RuntimeError("private-token")

    monkeypatch.setattr(forecast_cli, "GitHubFailureNotifier", broken)
    assert forecast_cli.main(["import-latest", "--root", str(tmp_path)]) == 0
    output = capsys.readouterr().out
    assert "artifact_missing" in output and "notification_failed" in output
    assert "private-token" not in output


def test_disabled_notifications_do_not_connect(forecasts, monkeypatch, capsys):
    monkeypatch.setattr(forecast_cli, "NotificationSettings", lambda: NotificationSettings())
    forecast_cli.report_failure(forecasts.sessions, FAILURE)
    assert "notification_disabled" in capsys.readouterr().out


@pytest.mark.parametrize(
    "change", [{"repository": None}, {"token": None}, {"token": SecretStr(" ")}]
)
def test_incomplete_configuration_never_connects(forecasts, change):
    notifier = GitHubFailureNotifier(forecasts.sessions, config().model_copy(update=change))
    with pytest.raises(ValueError, match="notification_not_configured"):
        notifier(FAILURE)


def test_request_budget_exhaustion_does_not_post(forecasts, monkeypatch):
    from farmable_backend import forecast_notifications

    clock = [0.0]
    github = FakeGitHub()

    def delayed(request):
        response = github(request)
        clock[0] = 21.0
        return response

    monkeypatch.setattr(forecast_notifications.time, "monotonic", lambda: clock[0])
    notifier = GitHubFailureNotifier(
        forecasts.sessions, config(), transport=httpx.MockTransport(delayed)
    )
    with pytest.raises(ValueError, match="notification_response_limit"):
        notifier(FAILURE)
    assert len(github.requests) == 1 and not github.issues
