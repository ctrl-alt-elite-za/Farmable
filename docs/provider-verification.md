# Provider verification for #7

These are operator tools, not automatic CI calls or proof that #7 is complete.
No accounts, secrets, billable requests, or deployment settings are provisioned
by this change. Keep #7 open until its remaining acceptance evidence is reviewed.

## Check one provider

The existing `make smoke` still checks every provider by default. Repeat
`--service` to select a subset; duplicate selections run once. Unselected
providers make no requests and receive no PASS line. A successful subset is not
an all-provider acceptance result.

```sh
make smoke SMOKE_ARGS="--live --allow-paid --service gemini"
make smoke SMOKE_ARGS="--live --allow-paid --service turnstile --service gemini"
```

Set `ENVIRONMENT=staging` and `INTEGRATIONS_MODE=live`, with the selected
providers' settings from [services.md](services.md). CI remains fake-only.
These flags acknowledge charges; get the account owner's approval first.
SMS additionally requires `--allow-sms` and the existing verified-recipient /
Fraud Guard prerequisites. Never paste credentials into command arguments or PRs.

Selecting `azure_stt` alone requires `--stt-wav PATH` to a nonprivate speech
fixture: mono, 16-bit PCM WAV at 16 kHz, up to 60 seconds and 2 MiB. It does not
silently call TTS to generate input. Selecting both Azure checks preserves the
existing TTS-to-STT test. Selecting crop health still requires all three crop
photos and genuine matching results; partial coverage is a failure.

## Check the Gemini Live client path

`make smoke-voice` uses an existing, verified Farmable access token. It does not
create a user, bypass login, connect to the database, or need `GEMINI_API_KEY`.
The configured backend holds that key and must already have Live issuance enabled
as described in [voice-live.md](voice-live.md).

Have an operator supply these environment variables securely, outside shell
history, logs and Git:

| Variable             | Required value                                                                                                     |
| -------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `ENVIRONMENT`        | `staging`                                                                                                          |
| `INTEGRATIONS_MODE`  | `live`                                                                                                             |
| `SMOKE_API_URL`      | Operator-approved staging Cloud Run HTTPS origin ending in `.run.app`, with no path, port, query or trailing slash |
| `SMOKE_EXPECTED_SHA` | Exact 40-character lowercase commit SHA deployed there                                                             |
| `SMOKE_ACCESS_TOKEN` | Existing 43-character Farmable access token for a phone- and email-verified test account; not its refresh token    |

Run locally from a trusted operator machine with the locked development
dependencies installed (`uv sync --locked`):

```sh
make smoke-voice SMOKE_ARGS="--live --allow-paid"
```

The CLI refuses CI, fake/disabled mode, missing authorization and malformed
configuration before calling a service. It first checks the backend's health
and SHA without sending credentials, then makes **one** bodyless authenticated
`POST /voice/live-session`. It requires no-store headers, a live v1beta token,
and fresh connection/expiry deadlines. The chosen URL is an operator trust
decision: a `.run.app` suffix alone does not prove project ownership or staging.

It connects to Google's fixed constrained Live WebSocket endpoint with the
ephemeral token in an Authorization header, not in the URL. HTTP and WebSocket
redirects and environment proxies are disabled. The setup matches the backend's
locked AUDIO/session-resumption configuration; no client tools are installed.
After setup acknowledgement it sends a fixed, nonprivate text prompt and requires
nonempty, valid 24 kHz PCM audio followed by turn completion. Audio is discarded,
not played, recorded or sent to another provider.

There are no mint or connection retries. HTTP calls have a 10-second timeout;
the setup phase has 10 seconds, the response turn 30 seconds, and the entire
operation 60 seconds, with a 2-second WebSocket close timeout. HTTP bodies are
limited to 32 KiB, WebSocket messages to 512 KiB, the exchange to 4 MiB and 256
messages, and the receive queue to four frames. Oversized, interrupted or
malformed responses fail. Failure/cancellation closes owned connections.

Only `PASS gemini_live audio_turn_completed` or a fixed failure code is printed.
Tokens, upstream messages, generated audio and exceptions are never output.
Record the exit status and fixed result alongside the tested deployment SHA and
UTC time. Do not capture wire/debug logs or dump environment variables. Clear the
local access-token environment variable after use and revoke the test session
through the supported account flow when available.

## What a PASS does and does not prove

A Live PASS proves the deployed authenticated mint path and one text-input /
audio-output exchange work for the configured account/model at that time. It
does **not** prove microphone capture, intelligible playback, speech recognition,
interruptions, planner tools, token reuse denial, expiry enforcement, session
resumption or Flutter device compatibility. The existing token-policy unit tests
remain synthetic evidence; those provider/device checks still need live tests.
No automatic fallback to an API key, alternate model or API version is allowed.

Google's [ephemeral-token guide](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens)
specifies v1beta and the `Token` authorization scheme. Its
[Python SDK implementation](https://github.com/googleapis/python-genai/blob/main/google/genai/live.py)
selects `BidiGenerateContentConstrained` for ephemeral tokens, but contains an
older v1alpha warning. This tool follows the current guide's v1beta and the
backend contract, with no version guessing. The exact wire path still requires
live acceptance; documentation-derived tests cannot establish provider support.
The bounded client uses [websockets 15](https://websockets.readthedocs.io/en/15.0.1/reference/asyncio/client.html)
as a locked development-only dependency; the production API image is unchanged.

Remaining #7 gates include real response recordings sanitized and reviewed before
commit, account/security configuration evidence, SMS/email delivery, Azure's
SDK silence behaviour, crop coverage and SoilGrids decisions, and consumer-level
failure handling. See [services.md](services.md) for the full checklist. These
tools prepare verification; they do not waive any production requirement.
