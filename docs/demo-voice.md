# Local voice-to-plan MVP

Related: #23, #24, #25, #26. **Partial hackathon slices, not production issue completion.**
The merged demo API now has a standalone English voice rehearsal page. It does not
modify the team's separate frontend or production API. It is a narrow command
interface, not a Gemini assistant or the specified Azure multilingual pipeline.

## Run on the presentation laptop

After the normal locked dependency setup, from the repository root:

```bash
uv run python -m farmable_backend.demo_api.init
uv run uvicorn farmable_backend.demo_api.app:app --host 127.0.0.1 --port 8001
```

Open `http://127.0.0.1:8001/demo/voice`. Keep one API worker and synthetic data only;
the [local API limits and setup](local-demo-api.md) still apply. No CDN assets,
new dependencies or server-side provider keys are needed for this page.

The browser must expose `SpeechRecognition` or `webkitSpeechRecognition`, permit
the microphone and run in a secure context (including trusted localhost).
**Test the actual installed browser before the presentation.** Recognition has
[limited browser support and can send audio to a vendor service](https://developer.mozilla.org/en-US/docs/Web/API/SpeechRecognition),
requiring internet. Browser synthesis voices may also use vendor services. This
is not an offline-voice claim or an Azure region/data-residency guarantee.

Explicit browser-speech consent is off on every page load. Without it, typing
and planning still work. Use only invented examples; do not dictate personal
data. Farmable stores no audio or transcripts. Browser/vendor behavior is not
controlled by the backend, so this is not suitable for real farmer data.

## The stage journey

1. Explore the example farm; select the available 400 m² section.
2. Compare/recalculate: the initial sample allocation is four spinach blocks.
3. Enable browser speech consent, tap the mic and say **"Keep at least half as cabbage."**
4. Review/correct the transcript, then click **Use reviewed message**. The allocation
   becomes cabbage/cabbage/spinach/spinach. The result is shown and, if available,
   read aloud. No plan is automatically saved or approved.
5. While playback is active, tap the mic. Playback is cancelled before listening
   starts. Say **"I only have two thousand one hundred rand."** Review and use it.
   The new sample allocation is cabbage/cabbage/spinach/unplanted, listed spending
   R2,100 and illustrative margin R1,100 after the listed costs.
6. Save proposal, approve explicitly and refresh. The planned planting reopens.
7. Try a R1,000 budget: the half-cabbage constraint is infeasible. No new plan is
   saved; the previously approved dashboard plan remains unchanged.
8. Reset this fictional farm for the next judge. Reset does not affect other sessions.

All crop, yield, price and cost inputs are invented fixtures. Leave the sample
label visible. This page does not assess soil/weather or prove actual income.
Only September 2026 planting dates are supported. Changing the controls invalidates
the old draft, so a stale displayed proposal cannot accidentally be saved.

## Supported commands

- `Compare cabbage and spinach` (retains existing constraints).
- `I only have R3000`, `My budget is R2,100.50`, `Set my budget to three thousand rand`.
- `Keep at least half as cabbage`, `Keep fifty percent cabbage`, `Keep 75% spinach`.
- `Plant cabbage` / `Plant only spinach` (sets that crop's minimum to 100%).
- One budget plus one share, in either order, joined with `and`.

Numeric rand amounts support up to two decimal places. Spoken whole amounts
support standard English numbers up to 999,999; controls support the full API
budget range. Other crop constraints are retained rather than silently removed;
contradictory shares return an infeasible result. Unsupported/ambiguous/negative
or unrelated phrases ask for a supported command and change nothing. This is
deliberately not broad natural-language understanding. Approving, resetting,
deleting, choosing dates and field selection use explicit controls only.

Recognition times out after 15 seconds. Permission/provider/unsupported-browser
failures retain the typing box. Speech-output errors retain the text reply.
Stop, tab hiding and page exit cancel listening/playback. Late callbacks from
an interrupted turn cannot overwrite the new transcript or speech state.

## Frontend integration

Use `SpeechController` from
`apps/backend/src/farmable_backend/demo_api/web/speech.mjs` as the browser adapter
reference. Recognition delivers an editable transcript, not a mutation.

```http
POST /demo/sections/{owned_section_id}/voice-preview
Authorization: Bearer <prototype_capability>
Content-Type: application/json
```

```json
{
  "transcript": "I only have R2100 and keep half cabbage",
  "controls": {
    "planting_date": "2026-09-18",
    "budget_cents": 300000
  }
}
```

The response contains `understood`, `reply`, complete updated `controls` and
`preview` (or null for an unrecognised command). Preview uses the token's owned
section area and never persists messages, plans or approvals. Do not send field
IDs/areas inside the controls. Save/approve through the existing keyed routes;
the companion page retries a lost save response with the same idempotency key.
Replies take monetary figures from the deterministic planner, not a language model.

Use the production UI's existing design when integrating; this page is a fallback
and a reference, not a replacement for the map experience. It has no map drawing.

## Evidence and limits

```bash
uv run pytest apps/backend/tests/test_demo_voice.py apps/backend/tests/test_demo_api.py -q
node --test apps/backend/tests/demo_speech.test.mjs
```

The Python suite also runs the fixed Node speech-state tests (Node is part of
normal repository setup). `FARMABLE_TEST_NODE` can select an installed local Node
executable when it is not on PATH. Tests use no microphone or paid speech calls.

Local browser verification used a real headless Edge page and HTTP API with
**injected speech events/output**, exercising review-before-use, interruption,
late callbacks, planning, approval/refresh, infeasible dates/budgets, reset,
permission failure and retry of a lost successful save response. That is not
proof of recognition accuracy, working venue internet, speakers or a physical mic.
Run the stage journey with real speech on the presentation laptop three times,
then record a private backup; retain typing/buttons for the venue.

Production Azure audio streaming/WebSockets, language switching, Gemini tool
conversation/history/SSE/evaluations, spend accounting, server-side stream
cancellation/partial reply persistence, native Maestro timings and #26's full
rehearsal remain unfinished. There is no upstream Gemini/TTS stream to cancel
in this browser-only prototype. Keep the full issues open.
