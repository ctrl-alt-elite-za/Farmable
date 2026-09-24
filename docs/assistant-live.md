# Conversation-scoped Gemini Live

Gemini Live remains the selected voice path. This adds backend consent and farm-tool
access to the existing direct-to-Google credential handoff. No Azure switch or
frontend redesign is included. The Flutter assistant sheet remains a placeholder:
this is **not** evidence of working device audio or completion of #7.

## Backend contract

Use the existing verified Farmable Bearer session and a farm-scoped assistant
conversation. All paths below start with `/assistant/conversations/{id}`.

- GET `/live-consent` returns the separate voice notice and configured Live model.
  Display it before requesting audio permission. An explicit user action can PUT
  `{notice_version, model}` to grant it; text consent is not voice consent.
- POST `/live-sessions` with `{id: <fresh UUID>}` mints one ephemeral credential.
  It returns the existing credential fields plus `id`, `lease_expires_at`, and
  the server-locked `setup`. No caller-defined model, instructions or tools are
  accepted. Neither credentials nor provider audio/transcripts are stored here.
- POST `/live-sessions/{session}/tools` relays `{id, name, args}` from a provider
  function call. The response is `{id, name, response}`. Only `list_sections`,
  `get_crop_outlook` and `preview_planting_plan` are allowed. Arguments are bounded
  and validated; all reads recheck farm ownership and voice consent. Permission
  is rechecked after the read before releasing its result.
- GET `/live-sessions/{session}` returns state, expiry, consumed tool attempts and
  `disconnect_required`. POST its `/interrupt` endpoint ends backend access
  durably and idempotently. This endpoint ends the whole session, not just a
  spoken answer.
- DELETE `/live-consent` withdraws permission and interrupts every issuing/active
  scoped session in the conversation. Regrant does not revive them. Credentials
  arriving after withdrawal, interruption or account deletion are withheld.

No model tool can approve a plan. The user must review the preview and explicitly
confirm using the separate [planning API](production-planning.md), which recomputes
the candidate and checks the snapshot. A voice assertion that a plan was saved is
not a saved record. Provider transcripts remain untrusted client-side content;
they are not inserted into durable text history by these endpoints.

## Client obligations (not implemented here)

Connect directly to Google's constrained v1beta Live WebSocket using the ephemeral
credential before `new_session_expires_at`. Use the returned setup; it fixes AUDIO
output, automatic activity interruption, transcription and the read-only tools.
Keep credentials in memory only, never in logs, analytics, URLs in diagnostics or
local persistence. Fake credentials cannot connect to Google.

On a provider `serverContent.interrupted` event, immediately stop playback and
discard queued audio from the interrupted answer. This is ordinary barge-in and
does not require ending the backend session. Do not send manual activity markers
while automatic activity detection is enabled. Discard cancelled tool-call results
instead of forwarding them after the provider cancels their IDs.

For Stop, withdrawal, logout, app teardown or a backend authority error, stop the
microphone and playback locally and close the provider socket immediately; do not
wait for a network response. Call the backend interrupt/withdraw endpoint as
appropriate. Poll the session state while connected and disconnect on
`disconnect_required`, failed authorization, loss of backend contact or the earlier
of `lease_expires_at` and `expires_at`. Do not automatically reconnect or mint a
new credential after an ambiguous failure.

The backend does not proxy audio and cannot close or revoke an already-issued
direct connection. A modified/non-cooperating client could continue using that
credential until its requested ten-minute expiry; provider resumption does not
reset expiry. Backend interruption stops farm-tool access, not already-sent data
or device audio. These limitations must remain visible in the consent experience.

See Google's [Live API contract](https://ai.google.dev/api/live) and
[ephemeral-token guide](https://ai.google.dev/gemini-api/docs/live-api/ephemeral-tokens).
Synthetic tests verify our request shape, not acceptance by the selected live model.

## Limits, retention and rollout

At most one issuing/active scoped session per owner (across farms and replicas),
with a ten-minute lease and 32 read-tool attempts. Invalid tool arguments and
retries consume admitted attempts; tool-call IDs are correlation IDs, not a
replay cache. Credential attempts share the legacy route's durable 3/minute and
20/hour rolling limits. Provider calls are never automatically retried.
These limits do **not** provide model-priced billing settlement or a project spend cap.

The legacy `/voice/live-session` compatibility endpoint remains unchanged: it has
no farm-tool capability or conversation consent binding. New farm-assistant clients
must use the scoped route; withdrawal here does not disable that legacy endpoint
or globally revoke the user's provider credentials.

Apply additive migration `0014` after `0013` before deploying this API. Independent
migration review is required. No implicit consent or existing-data backfill occurs.
Downgrading removes the voice consent/session metadata, not provider connections;
disable issuance and disconnect clients before rollback.

Content-free session metadata and voice consent receipts are owner-exportable and
retained until account deletion, which cascades their erasure. The separate text
history still expires after 30 days. Provider retention follows the operator's
terms and is not controlled by local deletion. No audio recording is uploaded to
Farmable through this contract.

Keep Live disabled until authorized provider and device acceptance. Test microphone
permissions, playback/barge-in, tool cancellation, withdrawal during minting and
playback, expiry/resumption, network loss and farm isolation on Android and iOS.
Zulu recognition/response quality has not been measured; do not claim equivalence
to Azure or that the former language-switching criterion has been demonstrated.
Actual cost settlement and the remaining #7 production criteria stay open.
