# Section mapping (#15)

Walk a section's edge, check the shape on a map, and save it — on the phone,
with no signal.

## The flow

Farm tab → **Map farm** (or **Edit boundaries**) → pick a section →
`/farm/zone/:id/boundary` (`?edit=1` opens the saved shape).

1. **Before** — what to do, and what this phone measures with.
2. **Walking** — the path drawn live (no map or network needed), area so far,
   GPS accuracy, and an optional **Mark corner**. When AR loses the ground a
   banner says so and AR drawing pauses; GPS keeps recording.
3. **Can't start** — location off or refused, with **Open Settings**.
4. **Review** — the shape on a map with draggable corners (+ adds one,
   long-press removes one), the area recalculated live, AR against GPS with a
   warning above 15%, and a self-crossing shape refused with the crossing
   sides in red and Save disabled.

Saving calls `updateSection(boundary: …)`: the GeoJSON `Polygon` goes into
`sections.boundary`, `area_source` becomes `boundary_estimate`, and the
existing outbox (#17) queues it for sync. Soil data is shown as *pending*
(account farms) or *unavailable* (the example farm) and never blocks saving;
fetching it is backend work in #11.

## Where the numbers come from

`lib/domain/mapping/geometry.dart` is a Dart port of `packages/geo` — same
rules, error codes and Earth radius — plus the pieces a walk needs:
Douglas–Peucker simplification to corners, and fitting a line to each side
so noisy GPS corners are not cut off. `lib/domain/mapping/walk.dart` turns a
stream of samples into the review shape:

- corners the farmer marked, if three or more;
- otherwise the AR path, simplified and rigidly aligned onto GPS;
- otherwise (GPS-only phones) the GPS path, thinned, simplified and
  straightened.

Agreement is `|AR − GPS| / max(AR, GPS)`; above 0.15 is a warning, not a
block. Fixes worse than 20 m are dropped and counted.

## Test mode: the fake AR source

A `TEST_MODE` build plays a recorded walk instead of walking a field
(`lib/data/mapping/recorded_walks.dart`), at 8× speed. Pick one with
`--dart-define=WALK_REPLAY=`:

| Name       | What it shows                                              |
| ---------- | ---------------------------------------------------------- |
| `field`    | AR + GPS over a 40 × 30 m (1 200 m²) field; AR loses tracking for a stretch. They agree. |
| `drift`    | Same walk, GPS 15% long on every side: the >15% warning.  |
| `gps-only` | No AR at all — a phone without ARCore.                     |

For a demo on an emulator:

```
flutter run --dart-define=TEST_MODE=true --dart-define=WALK_REPLAY=field
```

Covered by `test/mapping/*` (geometry, walk maths, every screen state) and
`e2e/mobile/map_section_replay.yaml` (area within 1%, saved with the API
down).

## Not done here — needs a phone

- **Real AR plane detection and AR path drawing.** Phones walk with GPS only
  today (`GpsWalkSource`, `hasAr: false`); the screen says so. AR needs a
  native ARKit/ARCore walk session feeding `WalkSample.ar` — the probe in
  `ar_probe.dart` proves the plumbing, not the walk.
- **Field-test evidence**, below.

## Field test (to be filled in by a person)

Walk a section whose size is known (measured with a tape, or from a survey),
once per phone. Record:

| Phone / OS | Mode (AR / GPS-only) | Known area | Measured | Error % | AR vs GPS % | Tracking losses | Notes |
| ---------- | -------------------- | ---------- | -------- | ------- | ----------- | --------------- | ----- |
| iPhone …   |                      |            |          |         |             |                 |       |
| Android …  |                      |            |          |         |             |                 |       |

Also check: permission refused → Settings → back works; airplane mode save,
then sync once online; editing a saved shape.
