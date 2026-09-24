# Outside services

Issue #7 implementation status: adapters and synthetic contract fixtures are
implemented; real-account acceptance is **not complete**. No accounts, keys,
quotas, Android restrictions, or Fraud Guard settings have been provisioned or
verified by this change. Do not close #7 on unit-test results alone.

## Authenticated Gemini Live credentials (#7 follow-up)

`POST /voice/live-session` now provisions a single-use, short-lived credential for
a verified Farmable user. It is separately disabled by default. See
[the endpoint contract and acceptance handoff](voice-live.md) for configuration,
quotas, failure behavior, and the remaining real-provider/Flutter checks.
This is backend credential provisioning, not a working microphone or voice UI.

The earlier demo prioritization is not the production acceptance scope. Issue #7
remains open for its provider requirements and transferred backend work. Existing
adapters must be verified, not rebuilt or treated as accepted solely because their
synthetic tests pass. PR #71 adds read-only text orchestration, not completion of
the whole issue; see [the acceptance map](assistant-backend.md#issue-7-acceptance-map).

## PR #36 scope and acceptance handoff

PR #36 is a **partial adapter foundation**, not completion of issue #7. Its
deliverables are the provider boundary, isolated synthetic fakes, bounded calls,
retry/circuit/fault controls, and an explicitly authorized staging-smoke command.
The startup-cleanup and stream-memory review findings have regression tests.
Merging this foundation does not establish that real accounts work or that
feature consumers degrade correctly. Issue #7 must remain open.

The remaining review requirements are tracked separately from automated checks:

| Requirement                              | Current evidence                                         | Needed for acceptance                                                           |
| ---------------------------------------- | -------------------------------------------------------- | ------------------------------------------------------------------------------- |
| Real staging smoke for every provider    | Not run; live calls are forbidden in CI                  | Configured staging accounts and explicitly authorized paid/SMS smoke output     |
| Fake vs recorded real-response contracts | Documentation-derived synthetic fixtures only            | Sanitized account-response recordings and comparison tests                      |
| Twilio account/security settings         | Not verified                                             | Account-owner confirmation of Fraud Guard, trial recipients, quotas and billing |
| Maps Android key restrictions            | Not verified                                             | Account-owner verification of package name and signing-certificate restrictions |
| Cabbage/spinach crop diagnoses           | Coverage not established                                 | Owner-approved provider or scope decision, followed by real-photo evidence      |
| SoilGrids availability                   | No live availability evidence                            | Restored service or an owner-approved replacement, then live smoke              |
| Azure 15-second initial-silence behavior | REST request timeout only; SDK semantics not implemented | Speech SDK implementation and silence-behavior verification                     |
| Consumer-level degradation E2E           | Adapter/application-boundary tests only                  | Feature E2E scenarios using isolated fakes once consumers exist                 |

Do not replace missing recordings with synthetic fixtures or label the REST
request budget as a silence timeout. An all-green smoke run proves only the
tested calls; the manual restrictions, recorded contracts, SDK semantics, and
consumer tests above remain separate acceptance requirements.

## Configuration and ownership

`apps/backend/src/farmable_backend/integrations/` is the sole provider boundary.
API lifespan owns `app.state.services`; reuse its adapters so each service keeps
its own circuit state. Worker startup validates the same safety settings.
Feature/job logic was outside the original adapter foundation. Issue #7 now also
owns the transferred assistant, voice, interruption and crop-diagnosis backend
requirements; their completion is separate from adapter-level verification.

`INTEGRATIONS_MODE=disabled` is the default: no provider calls. `fake` requires
`ENVIRONMENT=ci` or `staging` and always uses an isolated HTTP transport, even
if real keys happen to be present. `live` is forbidden in CI. Local development
can use live providers only through explicitly supplied environment variables.
Settings never automatically read `.env`, particularly not in CI. Compose
forwards service settings and faults to both API and worker; its test container
and isolated CI stack use `ci`/`fake`.

Every `FAULT_<SERVICE>` flag returns `unavailable` without a provider request.
Flags are rejected at API and worker startup outside CI/staging. Health readiness
continues to describe database/worker health, not paid-provider availability.
Tests cover the adapter/application boundary; graceful degradation of future
feature screens/endpoints must be checked when those consumers exist.

For the Google Cloud staging deployment, put sensitive values in the Terraform-
created Secret Manager containers and grant access only to the Cloud Run runtime
service account. The deployment injects them as environment variables without
printing values. The following are **proposed names**, not proof that versions
exist. Replace `staging` with the target environment and keep nonsecret
configuration separate. Do not dump a rendered environment or secret settings.

| Environment variable        | Secret Manager secret                        |
| --------------------------- | -------------------------------------------- |
| `TWILIO_ACCOUNT_SID`        | `farmable-staging-twilio-account-sid`        |
| `TWILIO_VERIFY_SERVICE_SID` | `farmable-staging-twilio-verify-service-sid` |
| `TWILIO_AUTH_TOKEN`         | `farmable-staging-twilio-auth-token`         |
| `TURNSTILE_SECRET`          | `farmable-staging-turnstile-secret`          |
| `TURNSTILE_HOSTNAME`        | `farmable-staging-turnstile-hostname`        |
| `AZURE_SPEECH_KEY`          | `farmable-staging-azure-speech-key`          |
| `AZURE_SPEECH_RESOURCE`     | `farmable-staging-azure-speech-resource`     |
| `AZURE_SPEECH_REGION`       | `farmable-staging-azure-speech-region`       |
| `GEMINI_API_KEY`            | `farmable-staging-gemini-api-key`            |
| `GEMINI_MODEL`              | `farmable-staging-gemini-model`              |
| `CROP_HEALTH_API_KEY`       | `farmable-staging-crop-health-api-key`       |
| `MAPS_SERVER_API_KEY`       | `farmable-staging-maps-server-api-key`       |

Azure region and resource name must match the created Speech account. No Gemini
model is guessed: set an available model explicitly, with its account quota.
Use a separate server Maps key; the Android key must be restricted to the app's
package name and signing certificate, manually verified in Google Cloud.

## Reliability and fallbacks

| Service        | Per-attempt bound                              | Fallback for feature consumers            |
| -------------- | ---------------------------------------------- | ----------------------------------------- |
| Twilio Verify  | 10 s                                           | No authentication success; retry later    |
| Turnstile      | 5 s                                            | Reject verification; retry widget         |
| Azure STT      | 15 s total request                             | Typed input                               |
| Azure TTS      | 10 s per submitted sentence                    | Display text                              |
| Gemini         | 10 s to visible first text / 60 s stream total | Explicit assistant-unavailable state      |
| crop.health    | 20 s                                           | Keep photo, show diagnosis unavailable    |
| SoilGrids      | 10 s                                           | Manual soil inputs / labelled cached data |
| Open-Meteo     | 10 s                                           | Labelled cached weather / unavailable     |
| Maps geocoding | 10 s                                           | Manual location selection                 |

Only network/timeouts, HTTP 429, and 5xx retry: at most three attempts, waits
0.5 s and 1 s plus 0–250 ms random jitter. Validation errors and other 4xx do
not retry. Five consecutive failed logical calls open that service's circuit
for 30 s; one successful call resets it. There is one half-open probe at a time.
Circuit state is per process and per service, not distributed across replicas.
Return stable failure codes, never provider exception strings or error bodies.
HTTP wire logs are suppressed; provider payloads/audio are excluded from repr.

Gemini preserves raw SSE parts, including thought signatures; thought-only
events do not satisfy the first-text deadline. No retry occurs after any event
has been delivered, avoiding duplicated streams. Stream cancellation closes
the response and releases the circuit probe. Total streaming deadlines include
retries/backoff. Nonstreaming Gemini requests have a 60 s per-attempt bound.
Each SSE response is limited to 2 MiB of decoded UTF-8 bytes (including comments
and framing), 256 JSON events, and 1 MiB per event/line. Limits are enforced
before buffering unterminated lines, and violations close the response with
`invalid_response`, without retrying. The smoke checker retains only summary
flags, not the sequence of provider payloads.

Azure short-audio REST accepts valid PCM WAV (mono, 16 kHz, 16-bit; at most
60 s). Its 15 s request budget is **not** the issue's SDK-level 15 s silence
timeout. Silence/partial streaming requires the Speech SDK and remains pending;
we do not invent an unsupported REST silence parameter. TTS callers should
submit one sentence per call. Returned binary audio is bounded to 10 MiB.

Retries after ambiguous POST timeouts can duplicate billable operations (SMS
or identifications). The smoke command uses **one attempt** per check to avoid
silently multiplying charges. Turnstile retries reuse one idempotency UUID and
validate literal success, expected hostname, and expected action.

## Staging smoke (explicitly billable)

Checks can now be selected with repeatable `--service` flags; omission keeps the
full suite. `make smoke-voice` separately checks the authenticated Gemini Live
client path with a temporary token. See [provider verification](provider-verification.md)
for exact opt-ins, bounds, prerequisites and what each PASS proves. Neither tool
is evidence of a live run until an authorized operator executes it successfully.

Set `ENVIRONMENT=staging`, `INTEGRATIONS_MODE=live`, all required configuration,
and `TWILIO_FRAUD_GUARD_CONFIRMED=true` only after checking the console. Supply
`SMOKE_PHONE` (a team-owned, trial-verified recipient), a fresh production-widget
`SMOKE_TURNSTILE_TOKEN` for action `sign_up`, and three local test photos.
Do not paste tokens or phone numbers into issue comments.

```sh
make smoke SMOKE_ARGS="--live --allow-paid --allow-sms --cabbage .env.smoke/cabbage.jpg --spinach .env.smoke/spinach.jpg --tomato .env.smoke/tomato.jpg"
```

To load a git-ignored `.env` locally, prefix the command with
`uv run --env-file .env`. Keep photos outside Git, for example in the ignored
`.env.smoke/` directory. Without authorization, staging/live
settings, or valid inputs, checks print `FAIL`, never a fabricated `PASS`.
`--allow-sms` explicitly authorizes one SMS; `--allow-paid` acknowledges account
charges. Missing SMS authorization fails that check without sending a message.
One request per service, except three separate crop identifications. TTS audio
is reused for STT, so no private transcript/microphone recording is needed.
Output contains fixed service labels and failure codes, never keys or payloads.
Any failure exits nonzero. An all-green smoke is necessary, not sufficient:
manual account/security settings and recorded-response contracts are still due.

## Provider facts and costs (checked 2026-09-17)

- [Twilio Verify](https://www.twilio.com/docs/verify/api/verification) uses a
  Verify Service, not direct messaging. Enable Fraud Guard manually. Confirm
  trial duration, credit, recipient limits and message-template restrictions in
  the [current trial documentation](https://www.twilio.com/docs/usage/trials)
  and your console. #7's assumed **30 days / $15.15 / five verified numbers /
  template messages only** is not verified account entitlement. Paid Verify
  and SMS charges depend on destination; check [pricing](https://www.twilio.com/en-us/verify/pricing).
- [Turnstile siteverify](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/)
  tokens are single-use and expire after five minutes. Test keys are not real
  account smoke evidence; the smoke command refuses documented test-secret prefixes.
- [Azure STT](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-speech-to-text-short)
  uses the custom Speech resource hostname;
  [TTS](https://learn.microsoft.com/en-us/azure/ai-services/speech-service/rest-text-to-speech)
  uses the regional endpoint. Limits/prices are subscription/tier-specific,
  charged by audio duration or generated characters; confirm F0/S0 quotas and
  [Speech pricing](https://azure.microsoft.com/en-us/pricing/details/speech/) before live tests.
- [Gemini](https://ai.google.dev/api/generate-content) model availability,
  token prices and rate limits depend on the model/tier. Record the chosen
  `GEMINI_MODEL` and [pricing](https://ai.google.dev/gemini-api/docs/pricing)
  before enabling billing; no paid request occurs in automated tests.
- [crop.health](https://www.kindwise.com/crop-health) is a credit-based
  identification service. Its published crop list includes **tomato but not
  cabbage or spinach**. The [documented API](https://crop.kindwise.com/docs)
  is `https://crop.kindwise.com/api/v1/identification` with `Api-Key`. Smoke checks
  diagnoses and matching crop predictions; it cannot make unsupported coverage
  pass. Provider choice/scope needs an owner decision before #7 can close.
- [SoilGrids REST status](https://docs.isric.org/globaldata/soilgrids/SoilGrids_faqs_02.html)
  says the beta service is temporarily paused with no restoration date.
  The published limit is five calls/minute. A mock success is not proof of live
  availability; smoke may fail until restored or an approved alternative exists.
- [Open-Meteo](https://open-meteo.com/en/docs) free access is for noncommercial
  use under its stated limits; commercial deployment needs the appropriate plan.
- [Google Maps Geocoding v4](https://developers.google.com/maps/documentation/geocoding/start-v4)
  requires billing and a restricted server key. Check SKU pricing/quotas in the
  account; never use the package/certificate-restricted Android key server-side.

## Evidence still required to close #7

1. Actual staging smoke output and configured account/region/quota evidence.
2. Verified Fraud Guard, team trial phones, Android package/certificate key restrictions.
3. Owner decision for unsupported cabbage/spinach coverage and paused SoilGrids.
4. Azure SDK 15 s silence semantics (current REST bound is only a request timeout).
5. Sanitized recorded real responses and contract tests comparing those recordings
   with fakes. `fixtures/provider_examples.json` is explicitly documentation-derived
   synthetic data, **not** a recorded account response. Never record real keys,
   access tokens, phones, locations, audio, or customer photos in fixtures.
