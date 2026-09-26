"""`make demo-ready` (#26): READY only when every check passes."""

from datetime import date

import demo_ready as ready

SHA = "a" * 40
TODAY = date(2026, 9, 27)


def staging(sha=SHA, database="ok", worker="ok", status="ok"):
    pages = {
        "/health/live": {"status": status, "sha": sha},
        "/health/ready": {"database": database, "worker": worker, "sha": sha},
    }
    return lambda url: pages[url[url.index("/health") :]]


def devices(sha=SHA, installed="2026-09-26", valid=7, margin=2):
    return {
        "devices": [
            {
                "platform": "ios",
                "build_sha": sha,
                "installed_at": installed,
                "signature_valid_days": valid,
                "warn_days_before_expiry": margin,
            }
        ]
    }


SCRIPT = "| # | Step | Says | Today |\n|---|---|---|---|\n| 1 | Sign up | Hi | ✅ yes |\n"


def sent(status=200, code=None):
    calls = []

    def post(url, body):
        calls.append((url, body))
        return status, code

    post.calls = calls
    return post


def check(**overrides):
    values = {
        "api_url": "https://staging.example",
        "sha": SHA,
        "devices": devices(),
        "script": SCRIPT,
        "today": TODAY,
        "probe_phone": "+27820000009",
        "send_code": True,
        "fetch": staging(),
        "post": sent(),
    }
    return ready.problems(**{**values, **overrides})


def test_everything_in_order_is_ready():
    assert check() == []


def test_staging_must_serve_the_event_build_and_be_healthy():
    assert check(api_url=None) == ["API_URL is not set: cannot check staging"]
    assert "not the event build" in check(fetch=staging(sha="b" * 40))[0]
    assert "database or worker" in check(fetch=staging(worker="down"))[0]

    def down(url):
        raise OSError("refused")

    assert check(fetch=down) == ["staging is unreachable (OSError)"]


def test_the_iphone_must_run_the_build_and_stay_signed():
    assert "the iPhone runs" in check(devices=devices(sha="c" * 40))[0]
    # Signed 2026-09-22: expires 09-29, two days away, inside the warning margin.
    expiring = check(devices=devices(installed="2026-09-22"))
    assert expiring == ["the iPhone's signature expires 2026-09-29 (2 days): re-sign it"]
    assert "lists no iPhone" in check(devices={"devices": []})[0]


def test_sign_up_codes_must_be_proven_not_assumed():
    # Without the probe, never "fine": staging may refuse every code request.
    assert "sign-up codes not checked" in check(send_code=False)[0]
    assert check(probe_phone=None) == [
        "--send-code needs DEMO_SIGNUP_PROBE_PHONE (a spare team number)"
    ]
    assert check(post=sent(503, "provider_unavailable")) == [
        "staging cannot send a sign-up code (HTTP 503, provider_unavailable)"
    ]
    assert "already has a staging account" in check(post=sent(409, "account_exists"))[0]


def test_the_probe_signs_up_the_spare_number_with_a_throwaway_email():
    post = sent()
    assert check(post=post) == []
    ((url, body),) = post.calls
    assert url == "https://staging.example/auth/signup"
    assert body["phone"] == "+27820000009"
    assert body["email"].endswith("@example.com")


def test_risky_script_steps_block_readiness():
    risky = SCRIPT + "| 6 | Scan | Boxes | ❌ Needs a model |\n| 9 | Plan | Confirm | ⚠️ Staging |\n"
    assert check(script=risky) == [
        "demo script step 6 is still marked ❌",
        "demo script step 9 is still marked ⚠️",
    ]


def test_main_prints_ready_or_every_problem(monkeypatch, capsys):
    monkeypatch.setattr(ready, "problems", lambda **_: [])
    assert ready.main(["--sha", SHA]) == 0
    out = capsys.readouterr().out
    assert "given with --sha" in out and "READY" in out
    monkeypatch.setattr(ready, "problems", lambda **_: ["one", "two"])
    assert ready.main(["--sha", SHA]) == 1
    out = capsys.readouterr().out
    assert "NOT READY" in out and "  - one" in out and "  - two" in out


def test_the_event_build_is_fetched_first_and_named(monkeypatch, capsys):
    monkeypatch.setattr(ready, "problems", lambda **_: [])
    monkeypatch.setattr(ready, "head_of_main", lambda: (SHA, True))
    assert ready.main([]) == 0
    assert "origin/main, fetched just now" in capsys.readouterr().out
    monkeypatch.setattr(ready, "head_of_main", lambda: (SHA, False))
    assert ready.main([]) == 1
    out = capsys.readouterr().out
    assert "NOT fetched" in out and "could not fetch origin/main" in out
