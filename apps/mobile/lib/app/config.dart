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

/// Where the app opens. `/` for every build anyone will ever install, and `/`
/// decides: a fresh install goes through the brand intro, onboarding and
/// auth choice once (issue #89); every launch after that opens on Home.
///
/// **What does not change is a product decision, not a tidying-up.** The seeded
/// demo farm has no user attached to it, and Home and Zone Detail are required
/// to work without a session and without a signal. The intro is shown once and
/// never again, reaching Home from it needs no account (Skip, then "Try the
/// demo farm"), and the answer to "has this phone seen it" lives on the phone
/// (`data/launch/launch_record.dart`) — a launch that cannot read it opens
/// Home. `e2e/mobile/*.yaml` walk the intro on a fresh install and then assert
/// that a second launch reaches Home with no taps.
///
/// Overridden only to photograph or drive a screen that sits several taps
/// down, so a capture is a build flag rather than a sequence of blind
/// coordinates on an emulator two sessions are sharing:
///
///   flutter build apk --debug \
///     --dart-define=INITIAL_ROUTE=/farm/zone/`section-id`/plant
///
/// The launch journey — brand intro, onboarding, auth choice — is reached the
/// same way, with `--dart-define=INITIAL_ROUTE=/splash`.
///
/// Safe because it can only reach routes the router already serves, and every
/// screen reads its own data by id — arriving here cold is the same code path
/// as arriving by tap, which `router.dart` calls a property of the
/// architecture. Every auth route is deep-linkable for the same reason. An
/// unknown path falls through to the router's own "nothing here" screen.
///
/// **One name on purpose.** This branch and the recommendations branch each
/// added a setting for this under a different name, and git merged both in
/// without reporting a conflict — two build flags doing one job, either of
/// which could have been the one nobody wired up.
const initialRoute = String.fromEnvironment('INITIAL_ROUTE', defaultValue: '/');

/// True when the app has no usable API and should present itself as offline
/// rather than appearing broken.
bool get isOfflineBuild => Uri.parse(apiUrl).host.endsWith('.invalid');
