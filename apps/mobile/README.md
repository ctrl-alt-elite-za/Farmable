# apps/mobile

The Expo **development build** (React Native) for iOS and Android. Not Expo Go: AR,
LiDAR and live detection cannot run there, or on an emulator (issue #4).

## Commands

Run these from the repository root.

| Command                             | Does                                           |
| ----------------------------------- | ---------------------------------------------- |
| `pnpm -C apps/mobile test`          | Jest + React Native Testing Library unit tests |
| `pnpm -C apps/mobile run typecheck` | `tsc --noEmit`                                 |
| `pnpm -C apps/mobile run prebuild`  | Regenerates `ios/` and `android/` from config  |
| `pnpm -C apps/mobile run ios`       | Builds and runs on a connected iPhone (macOS)  |
| `pnpm -C apps/mobile run android`   | Builds and runs on a connected Android phone   |
| `pnpm -C apps/mobile start`         | Metro, for a dev build already on a phone      |

`ios/` and `android/` are generated, gitignored build output - change
`app.config.ts`, never the native projects.

## Settings

The API URL is the only setting. Copy `.env.example` to `.env` and set
`EXPO_PUBLIC_API_URL` to a URL the **phone** can reach. No key or secret ever goes in
an `EXPO_PUBLIC_*` variable: those are inlined into the bundle.

`EXPO_PUBLIC_TEST_MODE=1` swaps live camera input for the recorded frames in
`src/testmode/fixtures/`, so camera features can be exercised on an emulator. A build
that sets it together with `EXPO_PUBLIC_DEMO_MODE=1` is refused by
`scripts/check-test-mode.sh` and by `src/testmode/source.ts`.

Android test-mode builds do not register Viro's native AR package: the pinned
SDK ships an ARM renderer but no x86_64 renderer, and otherwise crashes during
emulator startup. This is not an AR test or a passing AR capability result.
Physical builds still register Viro; iOS configuration is unchanged. Regenerate
the Android project with `--clean` when switching between test and device builds.

## Installing on the test phones

See [`docs/sideload.md`](../../docs/sideload.md). The **Self-test** tab runs the checks
that only work on a phone and uploads the result - contract in
[`docs/api/devices-self-test.md`](../../docs/api/devices-self-test.md).

## What is tested where

Jest covers the pure modules and the components that import no native library.
Everything native is covered by the Self-test screen on a real phone, because there is
no emulator that can run it.
