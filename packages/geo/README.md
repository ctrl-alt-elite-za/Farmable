# packages/geo

Pure TypeScript geometry for section walks; no network, filesystem or device access.

```ts
import { planarArea, geodesicArea, alignArToGps, applyAlignment } from '@farmable/geo';

const result = planarArea([
  { x: 0, z: 0 },
  { x: 20, z: 0 },
  { x: 20, z: 20 },
  { x: 0, z: 20 },
]);
if (result.ok)
  console.log(result.value); // 400 square metres
else console.log(result.error.code, result.error.message);
```

Every operation returns `Result<T>`, never an area for an invalid shape. Inputs are
not mutated. AR points are metres (`x` right, `z` forward; `y` ignored). GPS points
are WGS84 `{ latitude, longitude, accuracyMetres? }`; supply sensor accuracy when
available. Accuracy above 20 m, invalid bounds and nonfinite coordinates are rejected.
Runtime point entries are checked before property access: null, missing fields,
nonnumeric coordinates, array-shaped points and sparse holes return typed errors
instead of throwing. The public TypeScript point interfaces remain unchanged.
Null, nonobject, array-shaped or incomplete alignment objects return
`INVALID_ALIGNMENT` before any alignment fields are read.

- `closeShape` / `closeGpsShape`: remove consecutive and closing duplicates, reject
  crossings, self-touching, backtracking and zero area, and return a closed ring.
  Nonconsecutive repeated vertices are rejected, not silently removed.
- `planarArea`: orientation-independent square metres, stable at large AR offsets.
- `geodesicArea`: [Turf geodesic area](https://turfjs.org/docs/api/area), with longitude
  unwrapping for small fields crossing the dateline. Turf uses a mean-radius sphere
  on WGS84 coordinates, not an exact ellipsoidal survey calculation.
- `detectCorners`: absolute heading changes (default at least 45 degrees); indices
  refer to the cleaned open ring, excluding the repeated closing point.
- `smoothShape`: cyclic neighbor averaging of AR samples, protecting sharp corners
  and validating each pass. Options: strength 0–1 (default 0.25), iterations 0–100
  (default 1), corner threshold 0–180 degrees (default 45). Smoothing can change area;
  retain the original walk and preview the result before saving.
- `alignArToGps`: corresponding AR/GPS anchors (at least two distinct pairs), rigid
  least-squares rotation and east/north offset relative to the first GPS anchor.
  Positive rotation turns AR right toward north. Returns RMS fit error in metres;
  no scale is fitted. High residuals are reported, not hidden.
- `applyAlignment`: transforms another AR point into GPS coordinates.

Alignment and GPS topology checks use a local east/north projection with Turf's
mean Earth radius. They are intended for **farm-scale walks**, not continental
polygons or polar surveys. Alignment at the poles returns a typed error. A low fit
error indicates anchor consistency, not proof of sensor accuracy.

Run `pnpm -C packages/geo test` and `pnpm -C packages/geo typecheck` from the repo root.
Coverage enforces at least 90% for lines, statements, branches and functions across
all library source. The read-only `unit-tests` CI job uploads HTML, LCOV and JSON
summary output as `geo-coverage`; no privileged reporter executes it.

Synthetic fixtures live in `tests/fixtures/synthetic-walks.ts`. Issue #15 can add
sanitized recorded walks beside these fixtures without importing device APIs here.
