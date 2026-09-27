# Demo script (#26)

**Status: draft.** Rehearse it on the iPhone before it is final. Every step
lists whether it works on a real phone today. A step marked ⚠️ or ❌ must be
fixed, switched off with its feature flag, or replaced by the backup video
before the event.

- **Account:** a demo account on the **team phone number** (needed for the SMS
  code). Invented person and farm: *Thandi Mokoena*, *Thandi Farm*, sections
  *Cabbage Field* and *North Plot*. No real farmer's data appears on screen or
  in the video. Delete the account after the event.
- **Build:** the sideloaded release build whose SHA is in `docs/devices.json`,
  signed no more than 5 days before the event (free signing lasts 7).
- **Statistics:** none. The committed backtest reports *INSUFFICIENT
  EVIDENCE*, so the demo quotes no backtest figure.
  `python ml/backtest/check_demo_claims.py docs/demo-script.md` enforces this.
  Figures the app computes live (plan margins, areas) are shown, not claimed.
- **Backup video:** _path in the private bucket, recorded after the third
  passing rehearsal._

## Steps

| # | Step | What the presenter says | Works on a real phone today? |
|---|---|---|---|
| 1 | Open the app, walk through the intro, **Create account** | "Thandi farms two sections outside KwaMashu. She signs up with her phone number." | ⚠️ **Not working on staging yet:** every code request returns `503 provider_unavailable`, because no SMS provider is connected to sign-up. Fixed by whichever merges of #125 (Infobip) or #129 (Twilio Verify), plus that PR's console and secret setup. Then it needs the team phone for the code. |
| 2 | First farm and first section | "No title deed needed: a section is just a piece of land she uses for one thing." | ✅ First-launch setup (#89) |
| 3 | Home: greeting, sections, "Next up", harvest | "Everything here is on her phone. It opens the same with no signal." | ✅ Offline Home (#12) |
| 4 | Airplane mode, reopen, show the age label | "Out of coverage, nothing breaks. It says how old the numbers are." | ✅ (#12) |
| 5 | Farm → **Map farm** → walk North Plot → review → save | "She walks the edge; the phone works out the area." | ⚠️ GPS walk works (#15). AR tracing needs the field test (#115). Use GPS-only indoors. |
| 6 | Zone Detail → **Scan** a cabbage → **Start preview** | "This is a recorded preview of the scanning we are building: the phone boxes each plant and marks the ones worth a closer look. Live detection comes next." | ✅ As a **labelled preview, not live detection:** build with the `SCAN_PREVIEW` repository variable set to `true`. The screen says *Preview — recorded crop boxes, not live detections* throughout, and the presenter says so too. Live detection needs an approved model (#16, #18). |
| 7 | Write down an observation with a photo, offline, then signal back | "She notes aphids with no signal; it sends itself when the signal returns." | ✅ Offline upload (#17) |
| 8 | Insights → Alerts and Money | "What needs her, worked out on the phone; money to the cent." | ✅ (#93) |
| 9 | Assistant: *"Plan cabbage on North Plot"*, choose, review, confirm | "Nothing is saved until she taps Confirm." | ⚠️ Works end to end in CI with a fake model (#23). **Staging does not switch the assistant on** (no `ASSISTANT_*` settings in `infra/`, and no PR for them yet), so set its policy first. |
| 10 | Voice: ask, then tap to cut the answer off, then say `Only R3 000 though` | "She can interrupt it like a person." | ⚠️ Voice (#24) and interrupt (#25, PR #119) pass on fakes. Needs `GEMINI_LIVE_ENABLED` and `GEMINI_LIVE_MODEL` set as repository variables, which #130 wires into the deploy, and a real-phone check (#24). |
| 11 | Check a pen | — | ❌ Animal records are post-demo (#13). **Drop this step.** |

## Before the event

1. Fix every ⚠️ and ❌ above, or switch the feature off and use the video.
2. `make demo-ready` prints `READY` the day before (#26).
3. Three consecutive passing runs logged in `docs/demo-rehearsals.csv` for the
   event build SHA. Every failure becomes an issue labelled `demo-blocker`
   with its step number.
4. Timings in `docs/demo-timings.json`: each target met, or a linked
   mitigation issue.
5. Turn the deploy freeze on the morning of the event.
