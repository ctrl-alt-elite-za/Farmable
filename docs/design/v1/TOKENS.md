# Farmable — Design Tokens (v1, "Warm Paper")

Everything in this document is implemented in [`tokens.css`](tokens.css) as CSS custom
properties, and mirrored live on [`foundations.html`](foundations.html), which recomputes the
contrast table in the browser from the token values themselves.

Role names follow Material 3 so that the Flutter `ColorScheme` maps one-to-one, with three
product-specific extensions (`ink*`, `status/*`, `connectivity/*`) that Material 3 has no role
for. Those go into a `ThemeExtension`, not into unrelated M3 slots.

---

## 1. Colour

### 1.1 Light

| Role | Material 3 name | Hex |
|---|---|---|
| background | `background` / `surfaceDim` | `#F4F1EA` |
| surface | `surface` | `#FBFAF6` |
| surface-container | `surfaceContainer` | `#EDE9DF` |
| surface-container-high | `surfaceContainerHigh` | `#E4DFD2` |
| on-surface | `onSurface` | `#1C1B16` |
| on-surface-variant | `onSurfaceVariant` | `#4A473E` |
| outline | `outline` | `#6F6B5F` |
| outline-variant | `outlineVariant` | `#CFC9BA` |
| primary | `primary` | `#1D5233` |
| on-primary | `onPrimary` | `#FFFFFF` |
| primary-container | `primaryContainer` | `#C7E7D1` |
| on-primary-container | `onPrimaryContainer` | `#0A2C18` |
| secondary | `secondary` | `#5A4630` |
| on-secondary | `onSecondary` | `#FFFFFF` |
| secondary-container | `secondaryContainer` | `#EDDFC8` |
| on-secondary-container | `onSecondaryContainer` | `#2B2012` |
| tertiary | `tertiary` | `#1A4E72` |
| on-tertiary | `onTertiary` | `#FFFFFF` |
| tertiary-container | `tertiaryContainer` | `#CFE4F3` |
| on-tertiary-container | `onTertiaryContainer` | `#082D44` |
| ink-surface | *(extension)* `inverseSurface`-like | `#1E1F1A` |
| on-ink-surface | *(extension)* | `#EFECE1` |
| on-ink-surface-variant | *(extension)* | `#B7B2A3` |
| status-on-track | *(extension)* | `#18663A` |
| status-on-track-container | *(extension)* | `#C7E7D1` |
| on-status-on-track-container | *(extension)* | `#0A2C18` |
| **status-needs-attention** | *(extension)* | **`#8A5300`** |
| status-needs-attention-container | *(extension)* | `#FAE3BC` |
| on-status-needs-attention-container | *(extension)* | `#432700` |
| status-action-required | `error` | `#A31C12` |
| status-action-required-container | `errorContainer` | `#FBD9D4` |
| on-status-action-required-container | `onErrorContainer` | `#4C0B06` |
| **conn-offline** | *(extension)* | **`#455360`** |
| conn-offline-container | *(extension)* | `#DCE3EA` |
| on-conn-offline-container | *(extension)* | `#1C2831` |
| conn-syncing | *(extension)* | `#1A4E72` |
| conn-synced | *(extension)* | `#18663A` |

### 1.2 Dark

The page is **pitch black**. Surfaces are not — they stay warm charcoal and float on it, which
is what gives the dark theme its depth now that shadows are invisible against `#000`. Two
knock-on changes fall out of that, both noted in the table: the `ink-surface` counterpoint
inverts (it cannot be darker than the page, so it lifts), and the mockup's device bezel gets its
own token so a frame is still visible against a black page.

| Role | Hex |
|---|---|
| background | **`#000000`** |
| surface | `#1A1B16` |
| surface-container | `#232420` |
| surface-container-high | `#2C2E28` |
| on-surface | `#ECE9DE` |
| on-surface-variant | `#C2BEAF` |
| outline | `#928D7E` |
| outline-variant | `#4A4840` |
| primary | `#8ED3A3` |
| on-primary | `#032E17` |
| primary-container | `#2A5740` |
| on-primary-container | `#CAEFD6` |
| secondary | `#DCC49E` |
| on-secondary | `#2E2113` |
| secondary-container | `#4C3A25` |
| on-secondary-container | `#F0DEC2` |
| tertiary | `#8FCBEC` |
| on-tertiary | `#032F48` |
| tertiary-container | `#22506E` |
| on-tertiary-container | `#CBE6F7` |
| ink-surface | `#23241E` |
| on-ink-surface | `#ECE9DE` |
| on-ink-surface-variant | `#C2BEAF` |
| status-on-track | `#7ACB95` |
| status-on-track-container | `#22503A` |
| on-status-on-track-container | `#C3EBD1` |
| **status-needs-attention** | **`#F0B855`** |
| status-needs-attention-container | `#5A3E0B` |
| on-status-needs-attention-container | `#FBDFAE` |
| status-action-required | `#FF9186` |
| status-action-required-container | `#6B1C14` |
| on-status-action-required-container | `#FFD8D2` |
| **conn-offline** | **`#A9B7C5`** |
| conn-offline-container | `#333C45` |
| on-conn-offline-container | `#D5DFE8` |
| conn-syncing | `#8FCBEC` |
| conn-synced | `#7ACB95` |

### 1.3 The two ramps that must not touch

`status/needsAttention` sits on the **amber** ramp (hue ≈ 40°) and `connectivity/offline` on a
**neutral slate** (hue ≈ 210°, near-zero chroma). Neither hue is reachable from the red ramp by
any interpolation a future contributor is likely to reach for. This makes "offline looks like an
error" *unexpressible by accident*, rather than merely discouraged in a style guide.

This matters because of who the user is. Report §1.2 establishes that rural 4G is sparse and the
target user is on prepaid data and data-averse; report §9.1 designs the whole system so the
cloud is an enhancement, not a prerequisite. For this farmer, being offline is a Tuesday. An app
that flashes red at them every Tuesday teaches them the app is broken.

### 1.4 Scrim

Text over farm photography always sits on a scrim. There is no variant without one.

| Token | Value |
|---|---|
| `--scrim-strong` | `linear-gradient(to top, rgba(18,17,14,.88) 0%, rgba(18,17,14,.62) 34%, rgba(18,17,14,.12) 68%, transparent 100%)` |
| `--scrim-full` | `linear-gradient(to top, rgba(18,17,14,.80), rgba(18,17,14,.35) 55%, rgba(18,17,14,.22))` |
| `--scrim-top` | `linear-gradient(to bottom, rgba(18,17,14,.60), transparent)` |
| `--on-scrim` | `#FFFFFF` |
| `--on-scrim-variant` | `#E4E1D8` |

White on the scrim's base measures **14.23:1**. The scrim is identical in both themes: the sun
does not care which theme is selected.

---

## 2. Computed contrast — WCAG 2.1 relative luminance

Method: for each channel `c` in sRGB, `c' = c/12.92` if `c ≤ 0.04045` else `((c+0.055)/1.055)^2.4`;
`L = 0.2126R' + 0.7152G' + 0.0722B'`; ratio `= (L_light + 0.05) / (L_dark + 0.05)`.

Run it yourself: `node contrast.mjs` in `C:\Projects\farmable\design\`, or open
`foundations.html`, which does the same arithmetic against the live CSS values.

**130 pairs · 0 failures** — 82 solid pairs (lowest 4.72:1, `outline` on `background`, light)
plus 48 glass composite pairs (see §2.2).

Threshold is 4.5:1 for *everything*, including large text and icon-bearing chips, rather than the
3:1 that WCAG AA permits for large text. Justification is environmental, not legal: this screen is
read at arm's length in direct Highveld or KZN coastal sun on an entry-level LCD panel with a
poor polariser, frequently through a scratched screen protector.

### 2.1 Solid pairs

| Theme | Foreground | Background | Values | Ratio | |
|---|---|---|---|---|---|
| light | `onSurface` | `surface` | #1C1B16 on #FBFAF6 | **16.51:1** | PASS |
| light | `onSurface` | `background` | #1C1B16 on #F4F1EA | **15.29:1** | PASS |
| light | `onSurface` | `surfaceContainer` | #1C1B16 on #EDE9DF | **14.22:1** | PASS |
| light | `onSurface` | `surfaceContainerHigh` | #1C1B16 on #E4DFD2 | **12.96:1** | PASS |
| light | `onSurfaceVariant` | `surface` | #4A473E on #FBFAF6 | **8.89:1** | PASS |
| light | `onSurfaceVariant` | `background` | #4A473E on #F4F1EA | **8.23:1** | PASS |
| light | `onSurfaceVariant` | `surfaceContainer` | #4A473E on #EDE9DF | **7.66:1** | PASS |
| light | `onSurfaceVariant` | `surfaceContainerHigh` | #4A473E on #E4DFD2 | **6.98:1** | PASS |
| light | `outline` | `surface` | #6F6B5F on #FBFAF6 | **5.10:1** | PASS |
| light | `outline` | `background` | #6F6B5F on #F4F1EA | **4.72:1** | PASS |
| light | `onPrimary` | `primary` | #FFFFFF on #1D5233 | **9.10:1** | PASS |
| light | `onPrimaryContainer` | `primaryContainer` | #0A2C18 on #C7E7D1 | **11.38:1** | PASS |
| light | `primary` | `surface` | #1D5233 on #FBFAF6 | **8.72:1** | PASS |
| light | `primary` | `background` | #1D5233 on #F4F1EA | **8.07:1** | PASS |
| light | `onSecondary` | `secondary` | #FFFFFF on #5A4630 | **8.92:1** | PASS |
| light | `onSecondaryContainer` | `secondaryContainer` | #2B2012 on #EDDFC8 | **12.13:1** | PASS |
| light | `secondary` | `surface` | #5A4630 on #FBFAF6 | **8.54:1** | PASS |
| light | `onTertiary` | `tertiary` | #FFFFFF on #1A4E72 | **8.84:1** | PASS |
| light | `onTertiaryContainer` | `tertiaryContainer` | #082D44 on #CFE4F3 | **10.92:1** | PASS |
| light | `tertiary` | `surface` | #1A4E72 on #FBFAF6 | **8.46:1** | PASS |
| light | `onInkSurface` | `inkSurface` | #EFECE1 on #1E1F1A | **14.02:1** | PASS |
| light | `onInkSurfaceVariant` | `inkSurface` | #B7B2A3 on #1E1F1A | **7.83:1** | PASS |
| light | `statusOnTrack` | `surface` | #18663A on #FBFAF6 | **6.70:1** | PASS |
| light | `statusOnTrack` | `background` | #18663A on #F4F1EA | **6.20:1** | PASS |
| light | `statusOnTrack` | `surfaceContainer` | #18663A on #EDE9DF | **5.77:1** | PASS |
| light | `onStatusOnTrackContainer` | `statusOnTrackContainer` | #0A2C18 on #C7E7D1 | **11.38:1** | PASS |
| light | `statusNeedsAttention` | `surface` | #8A5300 on #FBFAF6 | **6.06:1** | PASS |
| light | `statusNeedsAttention` | `background` | #8A5300 on #F4F1EA | **5.61:1** | PASS |
| light | `statusNeedsAttention` | `surfaceContainer` | #8A5300 on #EDE9DF | **5.22:1** | PASS |
| light | `onStatusNeedsAttentionContainer` | `statusNeedsAttentionContainer` | #432700 on #FAE3BC | **10.97:1** | PASS |
| light | `statusActionRequired` | `surface` | #A31C12 on #FBFAF6 | **7.36:1** | PASS |
| light | `statusActionRequired` | `background` | #A31C12 on #F4F1EA | **6.81:1** | PASS |
| light | `statusActionRequired` | `surfaceContainer` | #A31C12 on #EDE9DF | **6.34:1** | PASS |
| light | `onStatusActionRequiredContainer` | `statusActionRequiredContainer` | #4C0B06 on #FBD9D4 | **11.77:1** | PASS |
| light | `connOffline` | `surface` | #455360 on #FBFAF6 | **7.56:1** | PASS |
| light | `connOffline` | `background` | #455360 on #F4F1EA | **7.00:1** | PASS |
| light | `connOffline` | `surfaceContainer` | #455360 on #EDE9DF | **6.51:1** | PASS |
| light | `onConnOfflineContainer` | `connOfflineContainer` | #1C2831 on #DCE3EA | **11.61:1** | PASS |
| light | `connSyncing` | `surface` | #1A4E72 on #FBFAF6 | **8.46:1** | PASS |
| light | `connSynced` | `surface` | #18663A on #FBFAF6 | **6.70:1** | PASS |
| light | `scrimText` | `scrimBase` | #FFFFFF on #2B2B26 | **14.23:1** | PASS |
| dark | `onSurface` | `surface` | #ECE9DE on #1A1B16 | **14.25:1** | PASS |
| dark | `onSurface` | `background` | #ECE9DE on #000000 | **17.28:1** | PASS |
| dark | `onSurface` | `surfaceContainer` | #ECE9DE on #232420 | **12.85:1** | PASS |
| dark | `onSurface` | `surfaceContainerHigh` | #ECE9DE on #2C2E28 | **11.30:1** | PASS |
| dark | `onSurfaceVariant` | `surface` | #C2BEAF on #1A1B16 | **9.29:1** | PASS |
| dark | `onSurfaceVariant` | `background` | #C2BEAF on #000000 | **11.28:1** | PASS |
| dark | `onSurfaceVariant` | `surfaceContainer` | #C2BEAF on #232420 | **8.37:1** | PASS |
| dark | `onSurfaceVariant` | `surfaceContainerHigh` | #C2BEAF on #2C2E28 | **7.37:1** | PASS |
| dark | `outline` | `surface` | #928D7E on #1A1B16 | **5.20:1** | PASS |
| dark | `outline` | `background` | #928D7E on #000000 | **6.33:1** | PASS |
| dark | `onPrimary` | `primary` | #032E17 on #8ED3A3 | **8.21:1** | PASS |
| dark | `onPrimaryContainer` | `primaryContainer` | #CAEFD6 on #2A5740 | **6.25:1** | PASS |
| dark | `primary` | `surface` | #8ED3A3 on #1A1B16 | **9.09:1** | PASS |
| dark | `primary` | `background` | #8ED3A3 on #000000 | **12.00:1** | PASS |
| dark | `onSecondary` | `secondary` | #2E2113 on #DCC49E | **8.56:1** | PASS |
| dark | `onSecondaryContainer` | `secondaryContainer` | #F0DEC2 on #4C3A25 | **7.34:1** | PASS |
| dark | `secondary` | `surface` | #DCC49E on #1A1B16 | **10.11:1** | PASS |
| dark | `onTertiary` | `tertiary` | #032F48 on #8FCBEC | **8.31:1** | PASS |
| dark | `onTertiaryContainer` | `tertiaryContainer` | #CBE6F7 on #22506E | **6.39:1** | PASS |
| dark | `tertiary` | `surface` | #8FCBEC on #1A1B16 | **9.83:1** | PASS |
| dark | `onInkSurface` | `inkSurface` | #ECE9DE on #23241E | **12.87:1** | PASS |
| dark | `onInkSurfaceVariant` | `inkSurface` | #C2BEAF on #23241E | **8.40:1** | PASS |
| dark | `statusOnTrack` | `surface` | #7ACB95 on #1A1B16 | **8.17:1** | PASS |
| dark | `statusOnTrack` | `background` | #7ACB95 on #000000 | **10.80:1** | PASS |
| dark | `statusOnTrack` | `surfaceContainer` | #7ACB95 on #232420 | **7.37:1** | PASS |
| dark | `onStatusOnTrackContainer` | `statusOnTrackContainer` | #C3EBD1 on #22503A | **6.42:1** | PASS |
| dark | `statusNeedsAttention` | `surface` | #F0B855 on #1A1B16 | **9.66:1** | PASS |
| dark | `statusNeedsAttention` | `background` | #F0B855 on #000000 | **11.69:1** | PASS |
| dark | `statusNeedsAttention` | `surfaceContainer` | #F0B855 on #232420 | **8.71:1** | PASS |
| dark | `onStatusNeedsAttentionContainer` | `statusNeedsAttentionContainer` | #FBDFAE on #5A3E0B | **7.28:1** | PASS |
| dark | `statusActionRequired` | `surface` | #FF9186 on #1A1B16 | **7.36:1** | PASS |
| dark | `statusActionRequired` | `background` | #FF9186 on #000000 | **9.65:1** | PASS |
| dark | `statusActionRequired` | `surfaceContainer` | #FF9186 on #232420 | **6.64:1** | PASS |
| dark | `onStatusActionRequiredContainer` | `statusActionRequiredContainer` | #FFD8D2 on #6B1C14 | **7.51:1** | PASS |
| dark | `connOffline` | `surface` | #A9B7C5 on #1A1B16 | **7.68:1** | PASS |
| dark | `connOffline` | `background` | #A9B7C5 on #000000 | **10.27:1** | PASS |
| dark | `connOffline` | `surfaceContainer` | #A9B7C5 on #232420 | **6.93:1** | PASS |
| dark | `onConnOfflineContainer` | `connOfflineContainer` | #D5DFE8 on #333C45 | **8.30:1** | PASS |
| dark | `connSyncing` | `surface` | #8FCBEC on #1A1B16 | **9.83:1** | PASS |
| dark | `connSynced` | `surface` | #7ACB95 on #1A1B16 | **8.91:1** | PASS |
| dark | `scrimText` | `scrimBase` | #FFFFFF on #000000 | **21.00:1** | PASS |

### 2.2 Glass composites

A backdrop-filtered surface has no fixed background — its effective colour depends on whatever
scrolls beneath it, so checking it against the nominal surface colour would be meaningless. Each
glass fill is instead composited over **pure black and pure white**, the two extremes any content
can reach, and every foreground role that sits on it is checked against both. Passing at both
extremes means passing over any possible content.

Worst case per fill (the lower of the two extremes):

| Theme | Foreground | Glass fill | Worst composite | Ratio | |
|---|---|---|---|---|---|
| light | `onSurface` | `glass-surface` over black | #E2E1DD | **13.18:1** | PASS |
| light | `onSurfaceVariant` | `glass-surface` over black | #E2E1DD | **7.09:1** | PASS |
| light | `primary` | `glass-surface` over black | #E2E1DD | **6.96:1** | PASS |
| light | `statusOnTrack` | `glass-surface` over black | #E2E1DD | **5.35:1** | PASS |
| light | `statusNeedsAttention` | `glass-surface` over black | #E2E1DD | **4.84:1** | PASS |
| light | `statusActionRequired` | `glass-surface` over black | #E2E1DD | **5.87:1** | PASS |
| light | `connOffline` | `glass-surface` over black | #E2E1DD | **6.03:1** | PASS |
| light | `onSurfaceVariant` | `glass-surface-high` over black | #DAD6CD | **6.40:1** | PASS |
| light | `scrimText` | `glass-on-imagery` over white | #6C6B6A | **5.32:1** | PASS |
| light | `scrimText` | `glass-on-imagery-strong` over white | #504F4D | **8.18:1** | PASS |
| dark | `onSurfaceVariant` | `glass-surface` over white | #353632 | **6.54:1** | PASS |
| dark | `statusOnTrack` | `glass-surface` over white | #353632 | **6.26:1** | PASS |
| dark | `statusNeedsAttention` | `glass-surface` over white | #353632 | **6.78:1** | PASS |
| dark | `statusActionRequired` | `glass-surface` over white | #353632 | **5.59:1** | PASS |
| dark | `scrimText` | `glass-on-imagery` over white | #676866 | **5.60:1** | PASS |
| dark | `scrimText` | `glass-on-imagery-strong` over white | #4A4A48 | **8.88:1** | PASS |

Lowest glass ratio in the system: **4.84:1** — light `statusNeedsAttention` on the nav island
when dark content scrolls beneath it.

Run `node contrast.mjs` for all 48 rows. Three of these failed on the first run — the fixes are
recorded in DECISIONS.md §3, and the alphas above are the corrected values.

---

## 3. Type

The app face is **San Francisco**, wired as a system-font stack rather than as a bundled or
served webfont.

```css
--font-display: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Inter',
                'Segoe UI', Roboto, system-ui, sans-serif;
--font-text:    -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Inter',
                'Segoe UI', Roboto, system-ui, sans-serif;
--font-numeric: var(--font-text);
```

What each device actually renders:

| Platform | Resolves to |
|---|---|
| iOS / macOS | **San Francisco**, from the OS's own copy |
| Android (the target device) | **Roboto**, unless a font is bundled |
| Windows / elsewhere | **Inter** where available, else Segoe UI |
| A designer with a licensed SF Pro installed | **SF Pro Display / Text**, locally only |

### 3.1 SF Pro is not bundled, and cannot be

Apple's Font Licence (<https://developer.apple.com/fonts/>):

> "The grants set forth in this License do not permit you to, and you agree not to, install, use or run the Apple Font for the purpose of creating mock-ups of user interfaces to be used in software products running on any non-Apple operating system"

> "You may not embed the Apple Font in any software programs or other products."

Farmable targets entry-level **Android**. Both clauses apply: SF cannot go in the APK, cannot
be served from our own origin, and is not even licensed for designing Android UI mock-ups.

Asking the OS for its own UI font is different and is fine — on an Apple device it is Apple's
operating system rendering Apple's own installed copy. Nothing is redistributed. That is the
standard licence-clean way to "use SF", and it is what this stack does.

### 3.2 The consequence worth naming

**The target user never sees San Francisco.** A Galaxy A13 renders Roboto. If the SF look
matters on Android the answer is to bundle **Inter** — SIL OFL, free to redistribute, the
closest widely-used face to SF — which is why Inter sits ahead of Roboto in the stack. The
top-bar **System / Android** switch renders both so the difference can be judged rather than
assumed.

### 3.3 Floors restored to 14 / 13

The previous revision raised them to 15/14 for a narrow face. SF, Inter and Roboto are all
normal-width with large x-heights, and SF Pro Text is optically cut for small sizes, so the
original **14px body / 13px meta** floors are correct again and are back in place. Verified:
zero text overflow across all 16 frames at 390x844 and 360x640, in both System and Android
modes.

### 3.4 Numerals

One family now does everything. SF, Inter and Roboto all carry tabular figures, so
`font-variant-numeric: tabular-nums` keeps R17,400 above R10,600 on a grid in every fallback.
The separate `--font-numeric` token is retained as an alias in case that stops being true.

| Token | M3 role | Family | Size / line | Weight | Tracking |
|---|---|---|---|---|---|
| `--type-display-l` | displayLarge | SF Pro Display | 36 / 40 | 400 | −0.02em |
| `--type-headline-l` | headlineLarge | SF Pro Display | 30 / 36 | 600 | −0.02em |
| `--type-headline-m` | headlineMedium | SF Pro Display | 26 / 32 | 600 | −0.02em |
| `--type-headline-s` | headlineSmall | SF Pro Display | 22 / 28 | 600 | −0.02em |
| `--type-title-l` | titleLarge | SF Pro Display | 20 / 26 | 600 | −0.02em |
| `--type-title-m` | titleMedium | SF Pro Text | 17 / 24 | 600 | 0 |
| `--type-title-s` | titleSmall | SF Pro Text | 15 / 20 | 600 | 0 |
| `--type-body-l` | bodyLarge | SF Pro Text | 16 / 24 | 400 | 0 |
| `--type-body-m` | bodyMedium | SF Pro Text | 15 / 22 | 400 | 0 |
| `--type-body-s` | bodySmall | SF Pro Text | **14 / 20** | 400 | 0 |
| `--type-label-l` | labelLarge | SF Pro Text | 15 / 20 | 600 | 0 |
| `--type-label-m` | labelMedium | SF Pro Text | 14 / 18 | 600 | 0 |
| `--type-label-s` | labelSmall | SF Pro Text | **13 / 16** | 600 | 0 |
| `--type-numeric-xl` | *(extension)* | system tnum | 34 / 38 | 600 | −0.02em |
| `--type-numeric-l` | *(extension)* | system tnum | 24 / 28 | 600 | −0.02em |
| `--type-numeric-m` | *(extension)* | system tnum | 18 / 22 | 600 | −0.02em |

Tracking tokens: `--tracking-tight` −0.02em, `--tracking-normal` 0, `--tracking-wide` 0.04em,
`--tracking-caps` 0.08em (uppercase eyebrow labels only).

**Currency and units.** ZAR renders `R17,400` — `R`, no space, comma thousands separator, no
decimals above R100; cents only for unit prices (`R4.60 per head`). Areas in hectares to one
decimal (`2.4 ha`), durations in days (`92 days`), rainfall in mm.

---

## 3.5 Brand assets

Supplied by the user as the **Almanac app kit**. They live in `assets/brand/` and are used
as given — nothing is recoloured or redrawn.

| File | Source | Used for |
|---|---|---|
| `launch.svg` | App kit.svg | The native launch screen, full bleed |
| `intro.gif` | App kit.gif | The animated brand intro |
| `lockup-light.svg` | App kit (3).svg | Mark + wordmark, dark type — for light surfaces |
| `lockup-dark.svg` | App kit (4).svg | Mark + wordmark, white type — for dark surfaces |
| `logo.svg` | App kit (2).svg | The original square lockup, kept as the master |
| `mark.svg` | *derived* | Mark only, no wordmark — for small placements |

**The mark-only file is derived, not supplied.** The kit ships lockups; the AI button renders
the logo at 30px, where a wordmark is an illegible smudge. `mark.svg` is the kit's own mark
group with the wordmark and background removed and the viewBox tightened to the measured
bounding box — no paths were altered.

**Small placements use a CSS mask, not an inline SVG:**

```css
.brand-mark {
  background: currentColor;
  mask: url('assets/brand/mark.svg') no-repeat center / contain;
}
```

The mark carries 13 `clipPath` ids; inlining it into 90+ device frames would duplicate every
one of them. A mask is a single cached request, tints to `currentColor` so the glyph follows
the button (white on green in light, dark on mint in dark), and costs no DOM.

The lockups are swapped by theme rather than recoloured, so the supplied artwork is never
altered:

```css
.brand-lockup.on-dark { display: none; }
[data-theme="dark"] .brand-lockup.on-light { display: none; }
[data-theme="dark"] .brand-lockup.on-dark  { display: block; }
```

### Brand palette (from the kit)

| Colour | Role in the kit |
|---|---|
| `#012120` | Deep teal — launch background, wordmark on light |
| `#0d9984` | Teal — the stem |
| `#82d89a` | Mint — the leaf, and the "Offiline" line on the splash |
| `#3e5725` | Olive — a minor accent |
| `#ffffff` | Wordmark on dark |

**These do not match the current token palette**, whose primary is `#1D5233`. The mark sits on
the green button without clashing, but the two are not the same family. Re-deriving `primary`
and `primary-container` from `#0d9984` / `#82d89a` would unify them — it is a contained change
(the contrast table would need re-running, which is one command) and it is flagged as an open
question rather than done unilaterally.

---

## 4. Spacing

4px base. `--sp-1` 4 · `--sp-2` 8 · `--sp-3` 12 · `--sp-4` 16 · `--sp-5` 20 · `--sp-6` 24 ·
`--sp-7` 32 · `--sp-8` 40 · `--sp-9` 48.

Screen gutter `--gutter` 20px. Minimum touch target `--touch-min` 48px, applied to every
interactive element including the timeline edit affordance and nav destinations.

## 5. Radii

`--r-xs` 8 · `--r-sm` 12 · `--r-md` 16 · `--r-lg` 20 · `--r-xl` 28 · `--r-2xl` 32 · `--r-pill` 999.

`--r-frame-inset` 8px is the "mat" a card leaves around an image; the image's own radius is the
card radius minus that inset (32 → 26, 28 → 20).

## 6. Elevation

| Token | Value | Used by |
|---|---|---|
| `--elev-0` | none | flat rows, list items |
| `--elev-1` | `0 1px 2px rgba(28,27,22,.05)` | cards resting on paper |
| `--elev-2` | `0 6px 16px -10px rgba(28,27,22,.22)` | zone cards, hero, ink card |
| `--elev-3` | `0 12px 28px -16px rgba(28,27,22,.30)` | raised cards |
| `--elev-4` | `0 18px 44px -20px rgba(28,27,22,.40)` | nav island, AI button |
| `--elev-sheet` | `0 -8px 28px -12px rgba(28,27,22,.35)` | assistant sheet, camera panel |

Dark theme redefines all of these at higher opacity against black. One shadow per level.

### 6.1 Glass

Three blur strengths, and nothing outside them.

| Token | Value | Used by |
|---|---|---|
| `--blur-sm` | `blur(10px) saturate(115%)` | controls and badges sitting on photography |
| `--blur-md` | `blur(18px) saturate(120%)` | bottom nav island, sticky top bars |
| `--blur-lg` | `blur(28px) saturate(125%)` | assistant sheet, camera assistant panel |

| Fill | Light | Dark |
|---|---|---|
| `--glass-surface` | `rgba(251,250,246,.90)` | `rgba(26,27,22,.88)` |
| `--glass-surface-high` | `rgba(237,233,223,.92)` | `rgba(35,36,32,.92)` |
| `--glass-hairline` | `rgba(28,27,22,.10)` | `rgba(236,233,222,.12)` |
| `--glass-hairline-strong` | `rgba(28,27,22,.16)` | `rgba(236,233,222,.20)` |
| `--glass-on-imagery` | `rgba(18,17,14,.62)` | `rgba(10,11,8,.62)` |
| `--glass-on-imagery-strong` | `rgba(18,17,14,.74)` | `rgba(10,11,8,.74)` |

Every glass surface has a `@supports not (backdrop-filter: ...)` fallback to the equivalent
solid surface. Nothing is only legible because of the blur.

**Ambient glow** (`--glow-warm`, `--glow-cool`, applied via `.glow-top`) reproduces the
reference's corner glows as radial *gradients*, not blurred layers — same warmth, no compositor
cost.

## 7. Motion

| Token | Duration | Curve | Applies to |
|---|---|---|---|
| `--dur-micro` | 180ms | `--ease-standard` | tap feedback, chip toggle, badge change |
| `--dur-screen` | 300ms | `--ease-standard` | route push / pop |
| `--dur-sheet` | 380ms | `--ease-emphasised` | assistant sheet, camera panel |
| `--dur-hero` | 400ms | `--ease-emphasised` | zone card image → zone detail hero |

Curves: `--ease-standard` `cubic-bezier(.2,0,0,1)` · `--ease-emphasised` `cubic-bezier(.05,.7,.1,1)`
· `--ease-exit` `cubic-bezier(.3,0,1,1)`.

The carousel scale is **not** a duration — it is a pure function of scroll offset, recomputed in a
rAF-throttled scroll handler. Continuous tracking, never a snap after page change.

`prefers-reduced-motion: reduce` collapses all four durations to 1ms and disables the listening
rings and waveform loops. The listening state still reads, because it is also a word
("Listening…"), an icon change, and a status colour.

## 8. Icons

**Lucide** (ISC licence), 24×24 grid, 2px stroke, round caps and joins. 52 glyphs are inlined
into `farmable.js` rather than loaded from a CDN, so icons render with no network — the same
constraint the product itself lives under.

In Flutter: `lucide_icons`, or hand-exported SVG assets bundled in the APK. Do not substitute
Material Icons piecemeal; the stroke weights do not match.

Icons carry `width="20" height="20"` intrinsically so an icon dropped into a container with no
sizing rule renders sensibly rather than stretching. Every CSS size rule still overrides it.

**No icon stands alone in a core action.** Every quick action, nav destination, status badge and
confirm control pairs the glyph with a word. This is a hard rule from report §1.2: functional
English literacy among the target users is low, and icon-only interfaces fail them silently.
