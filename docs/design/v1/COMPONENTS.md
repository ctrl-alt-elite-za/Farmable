# Farmable — Components (v1)

One entry per component in section 60 of the frontend guide. Live on
[`components.html`](components.html) with every state rendered; screens that compose them are on
[`screens.html`](screens.html).

All 45 items of the guide's inventory are now built, so everything below exists on a page —
nothing in this document is aspirational.

Spacing values below refer to the tokens in [TOKENS.md](TOKENS.md).

---

## AppPrimaryButton

**Anatomy** — pill container › optional 20px leading icon › label (`label-l`).
**Metrics** — min-height 48px (`--touch-min`), horizontal padding `--sp-5` (20px), icon-label gap
`--sp-2`, radius `--r-pill`.
**Tokens** — `primary` on `on-primary`, `--elev-1`.
**States**
- *default* — filled `primary`.
- *pressed* — `scale(0.975)` over `--dur-micro`; no colour change, because on a cheap panel a
  tint shift is less legible than a size change.
- *disabled* — `opacity .45`, pointer-events none. Used on Create account until validation passes.
- *loading* — label becomes a present-tense verb ("Saving…") with a spinning `refresh` icon. The
  button never becomes a bare spinner; the farmer keeps the word.
- *block* — `width: 100%`, the default on mobile.

## AppSecondaryButton

Same metrics. `transparent` fill, 1.5px `primary` border, `primary` label. A third **tonal**
variant (`surface-container-high` on `on-surface`) carries neutral actions like Edit and Cancel so
that Confirm is never competing with two equally weighted buttons. A **danger** variant is
outline-only on `status-action-required` — destructive actions are never the heaviest element
on screen.

**Icon-only button** (`.btn-icon`) — 48×48, `--r-pill`, `surface-container`. On imagery it becomes
`--glass-on-imagery` (62% alpha) with `--blur-sm` and a 16%-white hairline, carrying `on-scrim`
content. **That alpha is not a taste choice**: at 44% a white back-arrow over bright sky measured
2.95:1. Always carries `aria-label`.

## FarmStatusBadge

**Anatomy** — pill › 15px status icon › word.
**Metrics** — padding `5px 11px 5px 9px`, gap 6px, `label-s` (13px), radius `--r-pill`.
**States** — four, each icon + text + colour, never colour alone:

| State | Icon | Container | Text |
|---|---|---|---|
| On track | `checkCircle` | `status-on-track-container` | `on-status-on-track-container` |
| Needs attention | `alert` | `status-needs-attention-container` | `on-status-needs-attention-container` |
| Action required | `alert` | `status-action-required-container` | `on-status-action-required-container` |
| Not planted | `circleDash` | `surface-container-high` | `on-surface` |

A `badge-scrim` variant is used over photography: `--glass-on-imagery-strong` (74% alpha) with
`--blur-sm`, measured at 8.18:1 over the worst case.

## ConstraintChip

**Anatomy** — pill › 15px icon › short phrase. **Metrics** — min-height 34px, padding `0 --sp-3`,
gap 6px, `label-s`, 1px `outline-variant` border on the neutral variant.
**States** — `neutral` (a fact: "92 days"), `ok` (green: "Within budget"), `warn` (amber:
"Water: medium"), `blocked` (red: "R2,800 over your R12,000").

The blocked state **names the breach in rands**. A crop that fails a constraint is shown and
explained, never silently filtered out — hiding it teaches the farmer nothing.

## OfflineBadge

`badge` on `conn-offline-container` / `on-conn-offline-container` with a `cloudOff` icon.
Variants in use: "Offline", "Offline map", "Offline vision active", "Voice saved on phone".
Sits top-left on the map preview and in the status bar row. Never red, never an alert icon.

## SyncIndicator

**Anatomy** — pill › 15px icon › short phrase. Padding `5px 10px`, `label-s`.

| State | Icon | Tokens | Copy |
|---|---|---|---|
| Synced | `checkCircle` | on-track container | "Synced" |
| Syncing | `refresh` (spinning) | tertiary container | "Syncing" |
| Pending | `upload` | offline container | "3 changes waiting" |
| Offline | `cloudOff` | offline container | "Offline" |

Pending uses the offline slate, not amber and not red: queued work is normal, not a warning.
Syncing never blocks the UI and never shows a modal.

## SectionHeader

**Anatomy** — title (`title-l`, display face, −0.02em) › optional sub-label (`label-s`, muted) ›
optional trailing action (`label-m` in `primary`, with `chevronRight`).
**Metrics** — margin `--sp-6` top / `--sp-3` bottom, baseline-aligned, trailing action has a 48px
min-height hit area even though it reads as text.

## FarmHeroCard

**Anatomy** — full-bleed farm image › `--scrim-strong` › top row (status badge, map icon button) ›
body (farm name `headline-s`, location `body-s` on `on-scrim-variant`, meta row of icon+value pairs).
**Metrics** — aspect 16:11, radius `--r-2xl`, body inset `--sp-5`, meta gap `--sp-2`/`--sp-3`.
**Tokens** — `--elev-2`, `--on-scrim`, `--scrim-strong`.
**Content** — Siyakhula Farm · KwaMashu, KwaZulu-Natal · 2.4 ha · 4 sections · R48,100 projected.
Tapping opens the Farm page via a hero transition (`--dur-hero`).

## ZoneCard

**Anatomy** — card acting as a **mat** (`--sp-2` padding on all sides, 26px extra at the bottom) ›
image at 4:5 in a 26px-radius well › `--scrim-strong` › top row (crop badge, and an attention
badge or pending-sync count when relevant) › figure block (`label-s` key + `numeric-l` value) ›
**label chip centred on the card's bottom edge, overlapping it by exactly half its height**
(`translate(-50%, 50%)`).
**Metrics** — card radius `--r-2xl`, image radius 26px, label chip min-height 42px, padding
`0 --sp-4`, `title-s`, `--elev-2`, max-width 86% so a long zone name truncates rather than
reaching the card edges.
**States** — the status dot in the label chip takes `on-track` / `attention` / `action` / `idle`,
and the status word appears in the badge row or the caption beneath, so the dot is never the only
carrier.
**Content** — Cabbage Field R17,400 · Tomato Section R22,100 (attention) · North Plot 0.7 ha
available · Spinach Beds R8,600 (2 changes waiting).

## ZoneCarousel

**Behaviour** — horizontal scroll-snap strip, item width 66% of the viewport, first and last items
margined by 17% so any card can centre. A rAF-throttled scroll handler computes each item's
distance from the viewport centre and sets `--s` (scale) and `--o` (opacity) continuously:
centre `1.0` / `1.0`, neighbour `≈0.88` / `0.78`. Transform origin `center bottom`, so cards
shrink toward the label chip rather than away from it.
**Not yet built** — infinite looping (guide §17). The current strip is finite; see
DECISIONS.md §7.

## HealthSummaryCard

**Anatomy** — gauge (86px SVG ring, 10px stroke, `stroke-dasharray` 251.2) with score
(`numeric-l`) and denominator › title, status badge, one-line summary › per-zone bars › full-width
secondary button.
**Metrics** — card padding `--sp-5`, gauge/body gap `--sp-4`, bar height 8px, radius 4px.
**Tokens** — ring track `surface-container-high`, fill by status role.
**Content** — 82 / 100, On track, "1 section needs attention", Cabbage 88 / Tomato 54 / Spinach 91.
Each bar is labelled with its zone name **and** a status badge, so the bar length is decoration
rather than the only signal.

## FarmMetric / metric row

**Anatomy** — 2-column grid with 1px `outline-variant` gaps acting as rules › per cell: icon +
key (`label-s`, muted), value (`numeric-m`, tabular), sub-line (`label-s`, muted).
**Metrics** — cell padding `--sp-3 --sp-4 --sp-4`, grid radius `--r-lg`.
**Variant** — `.profit` colours the value `status-on-track`.
**Content** — Current health Good · Expected profit R17,400 · Expected cost R10,600 (R6,200 spent
so far) · Harvest 92 days (around 21 Dec).

## QuickActionTile

**Anatomy** — 3-up grid › tile: 40px icon well (`primary-container`, `--r-sm`) › label
(`label-s`, 15px line-height, centred, wraps to two lines).
**Metrics** — min-height 96px, gap `--sp-3`, radius `--r-lg`, `--elev-1`.
**States** — pressed `scale(.97)` + `surface-container`.
**Content** — Add observation · Add expense · Add sale · Add task · Add section · Scan crop.
Verbs the farmer uses, never "Create financial transaction".

## FarmMapPreview

**Anatomy** — rounded well › map raster/vector › OfflineBadge top-left › "Open map" tonal button
bottom-right.
**Metrics** — radius `--r-xl`, 1px `outline-variant`, chip inset `--sp-3`.
**Content** — the four real zone polygons with names and status dots, the farm boundary as a
dashed line, the access track, the water tank, and the user's location. Offline it shows cached
tiles and says so; it is never replaced by an empty placeholder.

## Timeline / TimelineItem

**Anatomy** — 30px left rail with a 2px `outline-variant` spine › per item: 22px node, title
(`title-s`), when (`label-s`), optional note (`body-s`), optional cost (`label-s` + wallet icon),
trailing 40px edit button.
**Metrics** — item bottom padding `--sp-5`, node offset −30px, spine inset from top 8px / bottom 14px.
**States**

| State | Node | Detail |
|---|---|---|
| completed | filled `status-on-track`, white check | title in `on-surface-variant` |
| current | filled `primary`, 5px `primary-container` halo ring | carries the note and cost |
| upcoming | `surface` fill, **dashed** `outline-variant` border, empty | date only |
| overdue | filled `status-action-required`, white alert glyph | date text in the same red |

Every item is editable; tapping opens a bottom sheet with Edit / Mark complete / Reschedule /
Delete. AI-generated plans render through this same component — there is no separate "AI timeline".

## ObservationTile

**Anatomy** — 56px thumbnail (`--r-sm`) › head row (type `title-s` + date `label-s`) › note
(`body-s`, muted) › tag row.
**Tags in use** — "By voice" (mic), "CV: 81%" (warn chip), a SyncIndicator, and an expense chip
when the observation created one.
Rows are separated by a 1px `outline-variant` rule rather than by being individually carded.

## RecommendationCard

**Anatomy** — card as mat › 128px crop image (`--r-lg`) with a fit badge top-left › head (crop
name `title-l` + variety, muted `label-s`) › figures row (profit in `status-on-track`, cost in
`on-surface`, both `numeric-m` tabular) › ConstraintChip row › full-width secondary button.
**States** — *strong fit* (green `checkCircle` badge) and *weak fit* (amber `alert` badge). A weak
fit is still fully rendered with its numbers; the chips carry the reason.
**Content** — Cabbage R17,400/R10,600 strong · Beans R9,800/R4,600 strong · Tomatoes
R22,100/R14,800 weak, "R2,800 over your R12,000".

## ProposedChangeCard

The confirmation gate. **Nothing the assistant produces is written until Confirm is tapped.**

**Anatomy** — 2px `primary` border › header strip (`primary-container`, sparkles icon, "Proposed
observation · not saved yet") › body: target (`title-m`), timestamp (`label-s`), then either
labelled fields or a before/after diff › provenance chips › ConfirmActionBar.
**Metrics** — radius `--r-xl`, header padding `--sp-3 --sp-4`, body `--sp-4`, field key in
uppercase `label-s` at `--tracking-wide`.
**Variants**
- *new record* — Observation and Action recorded as labelled fields.
- *edit* — 3-column diff: Before (`surface-container`) › arrow › After (`primary-container`).
- *compact* (camera panel) — chips instead of fields, to fit a 36%-height panel.
**Provenance chips** — "From your voice note", "Will sync later". The farmer can always see where
a proposed record came from.

## ConfirmActionBar

**Anatomy** — `1fr auto auto` grid: Confirm (primary, with check icon) › Edit (tonal) › Cancel
(tonal). Padding `--sp-3 --sp-4 --sp-4`, gap `--sp-2`, buttons 46–48px.
Confirm is the only weighted control. Cancel is never styled as destructive — cancelling a
*proposal* destroys nothing.

## BottomNavIsland

**Anatomy** — a detached pill floating over the content: 4 destinations + an empty centre slot
that the AIActionButton docks into. Each destination is icon + label, never icon alone.
**Metrics** — inset `--sp-3` left/right and `--sp-4` from the bottom, height 64px, radius
`--r-pill`, grid `1fr 1fr 76px 1fr 1fr`, `--elev-4`, 1px `--glass-hairline` border.
**Surface** — `--glass-surface` with `--blur-md` (18px + 120% saturate). Content scrolls
underneath it; the scroll container carries `calc(var(--navbar-h) + 62px)` bottom padding so the
last card is never trapped beneath the island.
**States**
- *default destination* — `on-surface-variant`, 22px icon, 13px label.
- *active destination* — `primary` colour, 2.4 stroke weight, **and** a filled
  `primary-container` pill behind it (`inset: 4px -2px`). Three carriers for "you are here":
  colour, stroke weight, and the pill — so the active state survives a monochrome rendering.
- *no backdrop-filter support* — `@supports not` falls the island back to solid `--surface`.

The island is why the blur exists: it only reads as floating if you can see content moving
behind it, and that is only legible if the glass is blurred and high-alpha.

## AIActionButton

**Anatomy** — 64px circle docked above the bottom bar, logo glyph inside, three absolutely
positioned ring elements, and a word beneath it in the nav's label baseline ("Speak" /
"Listening" / "Speaking").
**Metrics** — 64×64, `--elev-4` plus a 4px ring in `--glass-surface` so it reads as sitting *on*
the island rather than punched through it. Dock bottom 22px, which puts the button's lower half
inside the island and raises its top ~25px proud of it; the label sits on the same baseline as
the other nav labels. On the camera screen (no island) the dock stays at 22px.
**States**

| State | Appearance |
|---|---|
| idle | `primary` fill, sprout glyph, label "Speak" |
| listening | `scale(1.08)`, mic glyph, three 2px rings scaling 1→1.7 and fading over 1800ms at 600ms offsets |
| understanding | logo contracts to `scale(.93)` and back on a 1100ms loop — **no spinner** |
| speaking | `tertiary` fill, volume glyph; the farmer talking over it returns to listening |

**Accessibility** — `aria-label` "Farm assistant. Hold to speak, or tap to start and stop."
Hold is never the only route in; tap-to-start / tap-to-stop is equally supported. Under
`prefers-reduced-motion` the rings do not animate and the state is carried by the glyph, the
colour and the word.

## VoiceWaveform

Nine 3px bars, 5→20px, `wf` keyframe at 900ms alternate with staggered delays, `currentColor`.
A `.static` variant renders a frozen waveform for screenshots and reduced-motion.

## AssistantSheet

**Anatomy** — dimmed backdrop (`--backdrop`) › sheet at **70%** height, radius `--r-2xl` top ›
40×4px drag handle › AI status row (34px avatar, state `label-m`, hint `label-s`, live waveform) ›
transcript › structured result cards.
**Metrics** — enters on `--dur-sheet` (380ms) `--ease-emphasised`; expands to ~90%; the dashboard
stays visible above it.
**Surface** — `--glass-surface` with `--blur-lg` (28px) and a `--glass-hairline-strong` top edge,
so the dimmed dashboard reads faintly through the sheet rather than being replaced by it.
**The transcript is deliberately subordinate**: `body-s`, `on-surface-variant`, inside a
`surface-container` well with a 3px left rule and an uppercase "YOU SAID" eyebrow. It is a receipt,
not a conversation. The answer is the cards below it. If this ever reads as a chat app, the
component has failed.

## AssistantCameraPanel

**Anatomy** — panel at **36%** height over a live camera › handle › status row › scrolling
transcript region › pinned compact ProposedChangeCard with its ConfirmActionBar.
**Metrics** — radius `--r-2xl` top, padding `0 --gutter --sp-3`; the AI button re-docks to
`calc(36% + 14px)` so it floats on the panel's edge.
**Surface** — `--glass-surface` with `--blur-lg`; the live camera stays faintly visible through
the panel, which keeps the farmer oriented to what they are pointing at.
The camera never stops. Confirm collapses the panel and leaves the camera running.
The 36% (rather than the guide's ~30%) is a deliberate deviation — see DECISIONS.md §6.

## EmptyState

**Anatomy** — dashed 1.5px `outline-variant` container › 56px icon well › headline (`title-m`) ›
one sentence of plain body (`body-s`) › one primary action.
**Metrics** — padding `--sp-7 --sp-5`, radius `--r-xl`, centred.
**Content** — each empty state says what the thing *is* before asking for it: "A section is one
piece of land you use for one thing — a bed, a row, a field." The health empty state mentions that
scanning works "without airtime or data", because that is the farmer's first objection.

---

# Form, settings and flow components

Added for the full inventory. Defined in `app-forms.css`.

## AppTextField

**Anatomy** — label (`label-m`, muted) › input shell › optional helper line.
**Metrics** — shell min-height 54px, radius `--r-md`, 1.5px `outline-variant`, padding
`0 --sp-4`, internal gap `--sp-3`.
**States** — default · focus (2px `primary`) · valid (`status-on-track` border) · error
(`status-action-required` border + helper in the same red with an alert icon) · with leading
icon · with trailing action (show/hide password).
**Phone variant** — a country block sits inside the shell, divided by a hairline, defaulting to
🇿🇦 +27 and still changeable.

## PasswordStrength

Three segments plus a word. **Weak** (red, 1 segment) · **Fair** (amber, 2) · **Strong**
(green, 3). The label always carries advice rather than a rule — "try three words you will
remember", never "must contain one uppercase and one symbol". Long passphrases are the target
(guide §8).

## OtpSlots

Six 58px boxes, radius `--r-sm`, `numeric-l` tabular. **Filled** takes a `primary` border;
the active slot adds a 2px border and a blinking caret. Visually six, logically one input, so
paste and SMS autofill work.

## Stepper

Used only by the OTP flow: `1 Phone → 2 Email`. States are *done* (green tick), *now*
(`primary`), *upcoming* (muted). Two steps in one flow — the guide is explicit that two OTP
fields must never sit side by side.

## SegmentedControl

Full-width pill, 4px inset track, 44px segments, selected segment lifts onto `surface` with
`--elev-1`. Used for Email/Phone on login, Map/Sections on the Farm tab, and the four Insights
categories. Icon + word in every segment.

## Switch

52×32 pill, 24px thumb, `primary` when on. `role="switch"` with `aria-checked`. Every consent
switch in Privacy defaults **off** and its label states what turning it on actually shares.

## SettingsRow

**Anatomy** — 38px icon well › title + optional subtitle › value and chevron, *or* a Switch,
*or* a status badge.
**Metrics** — min-height 56px, `--sp-3` vertical padding, 1px `outline-variant` divider.
**Danger variant** — title and icon well switch to the red ramp; used once, for Delete account.
Rows carry `min-width: 0` so an unbreakable token (an email address) wraps instead of forcing
the row wider than the screen.

## BottomSheetMenu

Glass sheet (`--blur-lg`) with a drag handle, a title, and 52px menu items. Carries the
timeline item actions (Mark complete / Reschedule / Edit / Delete) and the permission primer.
Destructive items are last and red.

## PermissionPrimer

Shown **before** the OS dialog, at the moment the feature is first used — never four system
prompts after signup. 76px icon, one-sentence reason in plain language, Continue and a real
**Not now**. Guide §43.

## Onboarding card

Fixed chrome, moving content: Skip top **left**, artwork in a `--r-2xl` well, copy below, and a
single progress bar that animates with the swipe (25 / 50 / 75 / 100%) rather than dots.

## BrandMark / BrandLockup

The supplied Almanac kit, used as given.

**BrandLockup** — mark + wordmark, as an `<img>`. Two files, swapped by theme:
`lockup-light.svg` (dark type) and `lockup-dark.svg` (white type). Used at 42px on Auth Choice.
Never recoloured with a filter; the right artwork is shown instead.

**BrandMark** — mark only, applied as a CSS mask so it tints to `currentColor`. 26×30 inside the
64px AI button, where it renders white on green in light and dark on mint in dark. The mask
avoids duplicating the mark's 13 clipPath ids across 90+ frames.

**Launch screen** — **fills the screen at any aspect ratio**, built as three layers rather than
one flat image:

| Layer | Source | Behaviour |
|---|---|---|
| Photograph | extracted from `App kit.svg` (1600×2124 JPEG) | `object-fit: cover`, flexes to fill whatever height is left |
| Gradient | CSS | fades the photo into the brand teal so the seam moves with the layout |
| Mark + headline | `lockup-dark.svg` + live text | positioned in safe insets, never cropped |

A single 1080×1920 (9:16) artwork cannot fill a ~19.5:9 phone: `contain` letterboxes and
`cover` crops the wordmark off the right edge. Layering removes the choice — the photo absorbs
the aspect difference and the content stays put. Headline is `display-l` in white with the
second line in `#82d89a`; the panel is `#012120`.

**It does not theme-switch** — a native splash is a fixed asset, and both theme frames are
identical on purpose.

**Brand intro** — `intro.gif`, `object-fit: cover`, filling the screen. Its composition is
centred, so cover crops evenly off the sides and loses nothing. Under `prefers-reduced-motion`
it falls back to a still.

The generic `sprout` Lucide icon is still used for non-brand meanings (growth observations,
"sections planted"). It is not the logo and should not be swapped for one.

## Finance chart

Stacked money-in / money-out bars by month, with a legend and no axis furniture. It earns its
place by answering one decision — when does money start coming back in — which is the test
guide §38 sets for any chart.

## MoneyRow / PriceRow

`MoneyRow` is a key/value line with tabular figures and a `total` variant. `PriceRow` adds a
direction-only sparkline (`vector-effect: non-scaling-stroke`, no axes, no gridlines) and always
states the price's age, because offline prices are stale by definition.

## AlertRow

40px tinted icon well › title › one sentence of consequence › timing. The tint comes from the
status ramp, and the same alert always appears contextually on Home or the affected section —
Insights is never the only place a warning lives.
