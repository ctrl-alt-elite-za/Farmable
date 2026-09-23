/// Everything the app reads from its build environment.
///
/// There are no secrets here and there must never be: values supplied with
/// `--dart-define` are compiled into the binary, so anyone holding the APK can
/// read them. The API base URL is the only setting that varies per build.
///
/// Carried over from the Expo app this replaces, because the reasoning still
/// holds — see scripts/mobile-api.mjs, which enforces the URL policy in CI.
library;

/// Missing configuration stays explicitly offline rather than pointing at a
/// phone-local address.
///
/// `10.0.2.2` (the emulator's view of the host) and `127.0.0.1` are the
/// tempting defaults and both are wrong in a release build: the app would look
/// like it worked on the developer's machine and silently fail on a real
/// phone. `https://api.invalid` cannot resolve anywhere, so the failure is
/// immediate and obvious instead of subtle.
const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'https://api.invalid',
);

/// Replaces live camera input with recorded frames, for emulators and CI.
const testMode = bool.fromEnvironment('TEST_MODE');

/// For showing the product to people. Never combined with [testMode] — a build
/// that was both would present recorded detections as live ones and nobody
/// watching could tell. `scripts/check-test-mode.sh` fails such a build.
const demoMode = bool.fromEnvironment('DEMO_MODE');

/// Stamped by CI so a report can be traced back to the build that produced it.
const buildSha = String.fromEnvironment('BUILD_SHA', defaultValue: 'unknown');

/// Where the app opens. `/home` for every build anyone will ever install.
///
/// Overridden only to photograph or drive a screen that sits several taps
/// down, so a capture is a build flag rather than a sequence of blind
/// coordinates on an emulator two sessions are sharing:
///
///   flutter build apk --debug \
///     --dart-define=INITIAL_ROUTE=/farm/zone/`section-id`/plant
///
/// Safe because it can only reach routes the router already serves, and every
/// screen reads its own data by id — arriving here cold is the same code path
/// as arriving by tap, which `router.dart` calls a property of the
/// architecture. An unknown path falls through to the router's own "nothing
/// here" screen.
const initialRoute = String.fromEnvironment(
  'INITIAL_ROUTE',
  defaultValue: '/home',
);

/// True when the app has no usable API and should present itself as offline
/// rather than appearing broken.
bool get isOfflineBuild => Uri.parse(apiUrl).host.endsWith('.invalid');
