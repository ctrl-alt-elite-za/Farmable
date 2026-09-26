# Fonts — nothing to install here

This folder is intentionally empty. The app face is **San Francisco**, and SF is not a file we
are allowed to put in it.

## Why there are no font files

`tokens.css` asks the operating system for its own UI face:

```css
--font-text: -apple-system, BlinkMacSystemFont, 'SF Pro Text', 'Inter',
             'Segoe UI', Roboto, system-ui, sans-serif;
```

On iOS and macOS that resolves to San Francisco, rendered by Apple's OS from Apple's own copy.
Nothing is downloaded and nothing is redistributed, which is the standard licence-clean way to
use SF on the web. On Android it resolves to **Roboto**. On Windows, **Segoe UI**. Anywhere
Inter is available it is preferred over those last two, because Inter is the closest
freely-licensed face to SF and keeps the design consistent off-Apple.

`'SF Pro Display'` and `'SF Pro Text'` are named in the stack so that a designer with their own
licensed copy installed locally sees the real optical sizes while working. That copy is theirs;
it is never served to anyone.

## Why SF Pro cannot be bundled

Apple's Font Licence, from <https://developer.apple.com/fonts/>:

> "The grants set forth in this License do not permit you to, and you agree not to, install, use
> or run the Apple Font for the purpose of creating mock-ups of user interfaces to be used in
> software products running on **any non-Apple operating system** or to enable others to do so."

> "You may not embed the Apple Font in any software programs or other products."

Farmable's target device is an entry-level **Android** phone — Tecno Spark, Infinix Hot,
Galaxy A13. Both clauses bite:

| | Allowed? |
|---|---|
| SF bundled in the Flutter APK | **No** — embedding is prohibited outright |
| SF served as a webfont from our server | **No** — that is redistribution |
| SF used to design Android UI mock-ups | **No** — explicitly excluded by the licence |
| OS resolving SF for our UI on an Apple device | **Yes** — Apple's own OS, Apple's own copy |

## What the Android build actually gets

Roboto, unless a font is bundled. If the SF *look* matters on Android, the answer is to bundle
**Inter** (SIL OFL, free to redistribute, designed in the same neo-grotesque vein and the
closest widely-used substitute). That is a real decision, not a workaround — flagged in
DECISIONS.md §11.

Use the **System / Android** switch in the mockup top bar to see both.
