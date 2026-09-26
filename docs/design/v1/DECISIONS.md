# Farmable v1 — Decisions

Written for someone who was not in the room. Where a decision was made for the South African
smallholder context rather than for taste, it says so explicitly.

The starting point was a reference template (a warm "Kernwerk" admin dashboard: paper-stone
background, amber accent, very large radii, floating pill nav, bento grid, one dark card,
heavy use of `backdrop-filter` and large blurred glow layers). The brief was to apply its
**design language** to Farmable's real screens and real content. What follows is what was kept,
what was changed, and why.

---

## 1. Kept from the reference: the paper-stone substrate

**Chosen.** Background `#F4F1EA`, surfaces `#FBFAF6`, containers stepping warm-grey.
**Rejected.** A white or cool-grey substrate.

The reference's warm bone palette turned out to be the single most transferable thing about it,
and for a reason the reference never had: **this app is used outdoors in direct sun.** A pure
white surface is the brightest object in the user's field of view at midday and forces a squint.
Paper drops roughly 4% luminance at no cost to legibility, and its warmth sits naturally next to
soil and foliage photography instead of fighting it.

## 2. Changed: the accent is green, not amber

**Chosen.** `primary` = deep agricultural green (`#1D5233` light / `#8ED3A3` dark).
**Rejected.** The reference's yellow/amber accent.

This was forced, not preferred. The prior token work established that **`status/needsAttention`
must be amber** so that it is unreachable from the red ramp. If amber is also the brand accent,
then every primary button, every active nav item and every focus ring speaks in the same colour
as "something on your farm needs attention" — and the status role becomes invisible through
sheer repetition. One of the two had to move, and the status role is the one with a safety
argument behind it. Amber is now *reserved*: it appears only where something genuinely needs a
look.

Green also carries a second job: it distinguishes `primary` (an action you can take) from
`status-on-track` (a fact about your farm) at different luminances of the same hue family, which
keeps the palette small without collapsing the meanings.

## 3. Glass: backdrop blur, reinstated at the user's direction

**Superseded decision.** v1 initially shipped with zero `backdrop-filter`, on the grounds that a
blurred translucent surface is a full-screen compositor readback every frame on a 4GB Tecno
Spark, competing with a CV pipeline already budgeted 80–400ms of CPU (report §9.2).

**Current decision.** The user reviewed that trade-off and asked for the blur back, and for the
bottom navigation to become a floating island. That is their call to make, and it is now the
design. What follows is how it was made safe rather than simply switched on.

**Three blur strengths, and no more.** `--blur-sm` 10px (controls and chips sitting on
photography), `--blur-md` 18px (the nav island and sticky top bars), `--blur-lg` 28px (assistant
sheet, camera panel). Every glass surface in the product resolves to one of these three. There
are no one-off blur values, and no decorative blurred *layers* — the ambient glow from the
reference is reproduced as a plain radial-gradient (`.glow-top`), which costs nothing, rather
than as a blurred element.

**The contrast promise had to be extended, not abandoned.** A translucent surface has no fixed
background: its effective colour depends on whatever scrolls beneath it. Checking glass text
against the nominal surface colour would be a lie. `contrast.mjs` now composites every glass
fill over **pure black and pure white** — the two extremes any content can reach — and checks
each foreground role that sits on it against both. Clear 4.5:1 at both extremes and it clears
over any possible content.

That check failed three times on the first run, which is the point of running it:

| Case | Ratio | Fix |
|---|---|---|
| light `statusNeedsAttention` on nav glass over dark content | 4.40:1 | glass alpha 0.86 → **0.90** |
| white icons on a translucent control over bright sky | 2.95:1 | control alpha 0.44 → **0.62** |
| same, dark theme | 3.47:1 | control alpha 0.48 → **0.62** |

The second one matters most and is the one a designer eyeballing a mock would ship: a
half-transparent dark circle behind a white back-arrow looks fine over soil and becomes
invisible over sky. Farm photography contains a lot of sky. The alphas are now high enough that
the glass reads as *frosted* rather than *tinted* — which is also closer to the reference.

Totals after the fixes: **82 solid pairs + 48 glass composite pairs = 130, 0 failures.**

**Fallback.** Every glass surface is wrapped in `@supports not (backdrop-filter: ...)` and falls
back to the equivalent solid surface. On a WebView without the filter the island is opaque paper
rather than an unreadable translucent smear. No screen depends on the blur to be legible.

**The remaining cost is real and is accepted.** On the target device the island, the sheet and
the camera panel each blur a region of the screen per frame. It is bounded — the island is
~64px tall, the panel and sheet only exist while the assistant is open — but it is not free, and
if frame pacing suffers on a real Tecno Spark the first thing to try is dropping `--blur-md` to
12px and `--blur-lg` to 18px, which changes the look very little. Flagged for device testing.

## 4. Rejected: the reference's neutral text ramp

The reference uses `stone-400` and `stone-500` on near-white for secondary text, and 10px
timestamps in the dark card. `stone-400` on `#F9F8F4` computes to about **2.9:1** — it fails AA
at any size, and the 10px text fails the brief's floor twice over.

Every foreground in Farmable was instead **computed**: 82 foreground/background pairs across both
themes, all ≥ 4.5:1, lowest 4.72:1. The threshold is 4.5:1 even for large text and icon-bearing
chips, where WCAG would permit 3:1, because of sun, cheap LCD panels and scratched screen
protectors — not because of a compliance checkbox. The numbers are in TOKENS.md §2 and are
recomputed live in the browser on `foundations.html`, so they cannot silently drift from the
tokens.

## 3a. Dark mode is pitch black

**Chosen.** `background: #000000` in dark, with surfaces left at warm charcoal (`#1A1B16` and up).
**Rejected.** The original `#121310` near-black page.

The user asked for it on looks, and it holds up on the constraints too: the target devices
increasingly ship OLED or OLED-like panels, where true black costs no backlight, and this is a
product used by someone watching their battery on a farm with unreliable charging.

Two things fall out of it that were not free:

- **Shadows stop working.** `--elev-*` in dark is black-on-black against a `#000` page. Depth now
  comes from the surface luminance step and the 1px `outline-variant` hairline on every card,
  both of which were already there. Nothing needed adding, but the shadow tokens are now
  decorative in dark and load-bearing only in light.
- **`ink-surface` inverts.** It exists as a *darker* counterpoint surface, and on a pitch-black
  page there is nothing darker to be. In dark mode it lifts to `#23241E` instead. Its `on*` pairs
  drop from 17.10:1 to 12.87:1 — still far clear of the floor.

The mockup's device bezel also became a token (`--device-bezel`), because a `#0C0D0A` bezel is
invisible against a black review page.

Re-verified after the change: **130 pairs, 0 failures.** Every dark foreground actually improved
against the page — `onSurface` went from 15.34:1 to 17.28:1.

## 4a. The bottom navigation is a floating island

**Chosen.** A detached glass pill, inset 12px from the screen edges and 16px from the bottom,
with the content scrolling underneath it and the AI button docked proud of its centre.
**Rejected.** A bar welded to the bottom edge.

This is the reference's floating pill nav, brought down to phone scale, and it is the single
change that does most to make the product read as finished rather than as a wireframe. It also
earns the blur: an island only makes sense if you can see content moving behind it, and content
moving behind it only works if it is blurred enough to stay legible.

Two details that matter. The active destination gets a filled `primary-container` pill behind it
— the reference's active-pill treatment, and a second non-colour carrier for "you are here"
alongside the icon weight and label colour. And the AI button carries a 4px ring in the island's
own glass fill, so it reads as sitting *on* the island rather than punched through it.

Cost: the island eats 16px of vertical space that a welded bar would not, and the scroll
container needs 62px of extra bottom padding so the last card is never trapped under it.

## 5. Rejected: the bento grid

The reference's central idea is a dense bento dashboard — nine information regions visible at
once. That is the right instinct for an admin managing 12,408 users, and the wrong one here.
Guide §15 is explicit that the dashboard must not resemble an admin panel, and report §1.2
explains why: low functional English literacy, and users who navigate primarily through WhatsApp
and camera interfaces.

Home is therefore a **single vertical column of large objects** — one greeting, one farm, one
carousel, one health card, one action grid, one map. What survives from the bento is the
*card vocabulary*: the mat around every image, the large radii, the pill chips, the dark ink
surface used as a counterpoint rather than as a second theme.

## 6. Deviation: the camera assistant panel is 36%, not 30%

Guide §35 asks for "around 30%". At 30% on a 390×844 frame the panel cannot hold a listening
state, a two-line transcript, a proposed record and a 48dp Confirm row without the Confirm
scrolling out of view — and Confirm is the one control in the entire product that must never be
hard to reach, because it is the gate on §59's rule that nothing is written without explicit
consent.

Resolution: the panel is 36%, the transcript region scrolls, and the proposed card with its
Confirm bar is pinned outside the scroller so it is always visible. The camera still occupies 64%
and stays live. If the orchestrator wants a strict 30%, the transcript has to go entirely — which
is a legitimate call, since the transcript is deliberately the least important thing in the panel.

## 7. Deferred: the infinite carousel

Guide §17 requires the zone carousel to loop infinitely with no visual jump. The scroll-driven
scaling is built and correct — centre 1.0, neighbours ≈0.88, tracked continuously against scroll
offset rather than snapped after a page change. **Looping is not built.** With four zones the
finite strip demonstrates the interaction honestly, and modulo index mapping is a Flutter
`PageView` concern that a CSS scroll-snap mockup would only fake. Flagged rather than faked.

## 8. Generated imagery instead of stock photography

**Chosen.** Every farm scene, crop portrait, plot map and camera frame is deterministic SVG,
generated in `farmable.js` from a seeded RNG.
**Rejected.** Unsplash URLs (as the reference uses).

Three reasons. The mockup must render its content with no network — the same constraint the
product lives under — and a broken image in a design review is worse than a modest one. (The two
Google fonts are the one remaining request; they fall back to system-ui.) Stock
photography of "African farming" is overwhelmingly wrong for this product: drone shots of
commercial monoculture, or documentary poverty imagery. And controlling the imagery's luminance
means the scrim tokens can be tested honestly rather than against a conveniently dark photo.

The scenes are drawn to read as **real small plots** — furrows in perspective, a water tank, fence
posts, a farmhouse, tilled bare earth on North Plot, sensor grain on the camera frame. They are
not photographs and are not pretending to be. Production swaps real photographs in behind the
same scrim tokens; nothing else changes.

## 9. Status is never colour alone, and offline is never an error

Every status in the system is **icon + word + colour**, in that order of reliability. The status
dot on a ZoneCard is always accompanied by the status word in the badge row or caption. The health
bars are always accompanied by a status badge. This is guide §18 and §51, and it is also the only
way the system survives a user with colour vision deficiency on a washed-out panel in sunlight.

Separately: `connectivity/offline` is a **neutral slate**, sync-pending is the same slate, and
neither ever borrows from the red ramp. "3 changes waiting" is phrased as a count, not a warning.
Report §1.2 and §9.1 make connectivity an enhancement rather than a prerequisite; the visual
language has to agree, or the product tells the farmer they are failing every time they walk out
of coverage.

## 10. The transcript is subordinate to the cards

Guide §29 and §58 both insist the assistant must produce actionable UI state, not paragraphs. The
concrete design move: the transcript is `body-s`, muted, inside a recessed well with a left rule
and an uppercase "YOU SAID" eyebrow — visually a **receipt of what was heard**, not a message in a
conversation. Below it sit the chips showing what the assistant extracted (budget, water, target
zone) and then the recommendation cards carrying every number.

The test applied throughout: if a screenshot of the assistant sheet could be mistaken for
WhatsApp, it has failed. It currently cannot be.

## 11. The type face is San Francisco — as a system stack, not a bundled font

**Chosen.** A system-font stack that resolves to San Francisco on Apple platforms, Inter where
Inter is available, and Roboto on Android.
**Superseded.** Agrandir Narrow (previous revision), and Bricolage Grotesque + Inter before it.
**Declined.** Shipping SF Pro files — as a webfont, in the repo, or in the Flutter build.

The user asked for San Francisco. It is wired the only way it legitimately can be for this
product, and the reason is worth stating plainly because it constrains the Android build.

**Apple's Font Licence forbids the obvious implementation.** From
<https://developer.apple.com/fonts/>:

> "The grants set forth in this License do not permit you to, and you agree not to, install, use or run the Apple Font for the purpose of creating mock-ups of user interfaces to be used in software products running on any non-Apple operating system"

> "You may not embed the Apple Font in any software programs or other products."

Farmable's target device is an entry-level **Android** phone. So: SF cannot be embedded in the
APK, cannot be served from our origin, and is not licensed even for *designing* Android UI
mock-ups. I did not download or install SF Pro for this work, and there are no font files in
the repo.

**What is fine, and what the stack does.** Asking the operating system for its own UI face is
a different act from redistributing a font. On an iPhone, `-apple-system` resolves to San
Francisco rendered by Apple's OS from Apple's own copy — nothing is transmitted by us. That is
the standard, licence-clean way to use SF on the web, and it is what `--font-display` and
`--font-text` do. `'SF Pro Display'` and `'SF Pro Text'` are named in the stack purely so a
designer with their own licensed copy sees the real optical sizes locally.

**The consequence the orchestrator must not miss: the target user never sees San Francisco.**
Sipho's Galaxy A13 renders Roboto. Choosing SF is therefore a choice about how the product
looks on *reviewers' and stakeholders' iPhones and Macs*, not on the farmer's phone. If the SF
look is wanted on the device that actually matters, the answer is to bundle **Inter** — SIL
OFL, free to redistribute, the closest widely-used face to SF — which is why Inter sits ahead
of Roboto in the stack and is the face most non-Apple viewers will actually get. A top-bar
**System / Android** switch renders both.

**Floors go back to 14/13.** They were raised to 15/14 for Agrandir Narrow. SF, Inter and
Roboto are normal-width with large x-heights, and SF Pro Text is optically cut for small sizes,
so the original floors are correct again. Verified: zero text overflow across all 16 frames at
both sizes, in both font modes.

**Numerals collapse back into one family.** SF, Inter and Roboto all carry tabular figures, so
there is no longer a reason to hold numerals on a separate face; `--font-numeric` remains as an
alias in case that changes.

A side benefit of landing here: the font payload is now **zero bytes on Apple and Android**,
and one free family elsewhere. On metered prepaid data — the constraint from report section 1.2
— that is the best possible outcome, and it is the one thing every previous type decision in
this document was trading against.

## 12. Floors, not guidelines

14px body, 13px meta, 48px touch targets. These are enforced through tokens rather than left to judgement: there is no type
token below the floor to reach for, and `--touch-min` is applied to the
timeline's small edit affordance and the SectionHeader's text links, not just to buttons. A
guideline gets eroded screen by screen; a missing token does not.

---

## 13. Building the remaining 39 screens

With the direction approved, the rest of guide §66 was built out. Four decisions were made
while doing it that are worth recording.

**The galleries were split by flow, not kept in one file.** `screens.html` (core),
`screens-auth.html`, `screens-farm.html`, `screens-insights.html`. One page of 94 device frames
would be slow to open and impossible to review. The shared scaffolding moved into
`screens-lib.js` and `screens.css` so the seven pages cannot drift apart, and generated scenes
are now memoised in `SCENE_CACHE` — the same SVG is built once per page rather than once per
frame.

**The native splash does not theme-switch.** Both frames are identical dark green. A launch
image is a fixed asset compiled into the app; if it followed the theme it would flicker against
the first Flutter frame, which is the one thing §5 says to avoid.

**Charts had to justify themselves.** Guide §38 forbids dense analytics. Two survived: the
money-in/money-out bars, which answer "when does cash start coming back", and direction-only
sparklines on market prices. Both are decision-shaped. No pie charts, no axis furniture, no
chart that only restates a number already on screen.

**Map tiles get a dark treatment.** The generated map is a fixed-colour raster, so on a
pitch-black screen it glared. Real map SDKs ship a dark style; `filter: brightness(.74)
saturate(.88)` approximates one. It is a static filter on a static image, rasterised once.

Two content decisions worth naming, both from report §1.2 rather than taste. First-farm setup
says outright that mapping needs no title deed, because informal tenure is the norm and "map my
farm" sounds legal. And Add Observation puts six icon tiles *before* any text field, with the
note explicitly optional — the farmer picks what they saw rather than composing a sentence.

## 14. The Almanac app kit

The user supplied a brand kit and directed where each piece goes: `App kit.svg` as the native
launch screen, `App kit.gif` as the animated brand intro, and the logo everywhere it appears.
All of it is wired in and used as given — no asset was recoloured or redrawn.

Two things had to be derived rather than taken:

**A mark-only file.** The kit ships lockups (mark + wordmark). The AI button renders the logo at
30px, where a wordmark is an illegible smudge. `mark.svg` is the kit's own mark group with the
wordmark and background stripped and the viewBox tightened to its measured bounding box. Paths
are untouched. If the brand owner has an official mark-only asset, it should replace this.

**A layered launch screen, so it fills.** The artwork is authored 1080×1920 (9:16); the target
frame is ~19.5:9. A single flat image can only letterbox (`contain`) or crop the wordmark off
the right edge (`cover`) — I shipped the letterboxed version first and the user correctly
rejected it: a splash must fill.

The fix is to stop treating the splash as one image. The photograph was extracted from
`App kit.svg` (a 1600×2124 JPEG, embedded in the SVG) and is now a `cover` layer that absorbs
the aspect difference; the mark and headline sit above it in safe insets and are never cropped.
It fills at 390×844, at 360×640, and at any aspect between. The headline is live text rather
than outlined vector, which also means it can be localised — the product has eleven official
languages to think about (report §1.2).

While re-setting the headline I spelled it **"Offline"**. The supplied artwork reads
**"Offiline"**. That is a correction, not a redesign, and the source file still needs fixing.

Five things the kit surfaced that need a decision, all in the report: the product is called
**Almanac** while every mockup still says Farmable; the GIF is **44.6 MB**; the splash reads
**"Offiline"**; the brand palette is **teal** where the tokens are green; and the artwork's
aspect ratio does not match a modern phone.

## Open questions for the orchestrator

1. **Is the green-primary / reserved-amber split accepted?** Everything else in the palette
   follows from it. If the brand must be amber-led, the needsAttention role has to move and the
   prior token work's conclusion needs revisiting.
2. **36% camera panel, or 30% with no transcript?** (§6)
3. **San Francisco never reaches the target user.** Android gets Roboto. Decide whether to
   bundle **Inter** in the Flutter build to carry the SF look onto the device that matters
   (free, redistributable, ~100KB subset), or to accept Roboto on Android and treat SF as the
   face for Apple viewers only. The top-bar **System / Android** switch shows both.
4. **Generated imagery** is a mockup convenience. Who supplies real KwaZulu-Natal smallholder
   photography, and does it need to be shot rather than licensed?
5. **Is the product Almanac or Farmable?** The kit's wordmark says Almanac; every screen title,
   page heading and document here says Farmable. One of them is wrong and it is a rename either
   way.
6. **The intro GIF cannot ship at 44.6 MB.** Re-export as WebM/animated WebP or rebuild as
   Lottie. At South African prepaid rates that single file is roughly R6–7 of data per install.
7. **"Offiline" on the launch artwork** — an extra *i*. The rebuilt splash sets it as live text
   and spells it correctly, but the source SVG still has the typo and other exports will carry
   it.
7b. **Android 12+ cannot show a full-bleed splash natively.** The platform SplashScreen API
   takes a background colour plus a centred icon — not an arbitrary image. So in production the
   *native* splash is brand teal + the mark, and this rich composition becomes the **first
   Flutter frame**, drawn immediately after. Getting the handover invisible means matching the
   teal and the mark's position exactly across that boundary. This is the main thing to get
   right when wiring it up for real.
8. **Align the token palette to the brand teal?** One command to re-verify contrast.
