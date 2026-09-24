/// Runs the real auth screens against the real demo service — or, with `api`,
/// against the real [ApiAuthService] over a fake of the backend.
///
/// Nothing here mocks [AuthService]. The screens are wired to
/// [DemoAuthService] over an in-memory [SessionStorage] with the clock pinned,
/// so a test that says "sign up, verify twice, restart, still signed in" is
/// exercising the same code path the farmer does, including the persistence.
/// A mocked service would pass these tests with a broken one.
///
/// It is kept separate from `harness.dart` rather than folded into
/// `pumpFarmApp`, because the auth screens need the session overridden and the
/// farm screens do not, and because PR #51 is editing that file at the same
/// time.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/app/router.dart';
import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/data/auth/api_auth_service.dart';
import 'package:almanac/data/auth/demo_auth_service.dart';
import 'package:almanac/data/auth/session_storage.dart';
import 'package:almanac/data/health_service.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/auth/auth_models.dart';
import 'package:almanac/features/auth/auth_view_model.dart';
import 'package:almanac/features/auth/widgets/auth_scaffold.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fake_auth_api.dart';
import 'harness.dart' show pinnedToday, phoneSize;

export 'harness.dart'
    show
        expectNoFailureLanguage,
        forbiddenFailureWords,
        pageScrollable,
        phoneSize,
        pinnedToday,
        revealOnPage;

/// The cheapest screen this product is built for. Every form is checked at
/// this size with the keyboard up, because it is where a field first goes
/// under the keyboard.
const compactPhone = Size(360, 640);

class _FixedHealth implements HealthService {
  final Reachability result;

  const _FixedHealth(this.result);

  @override
  Future<Reachability> check() async => result;
}

class AuthHarness {
  final AlmanacDatabase db;

  /// The record on "disk". Survives [restart], which is what makes the
  /// session-restore test a real one rather than a re-read of memory.
  final SessionStorage storage;

  final ProviderContainer container;

  AuthHarness._(this.db, this.storage, this.container);

  /// What the app would restore on its next cold launch.
  Future<AuthStanding> standing() =>
      container.read(authServiceProvider).restore();
}

/// Pumps the whole app — router and all — at the given auth route.
Future<AuthHarness> pumpAuthApp(
  WidgetTester tester, {
  String location = '/auth',
  Size surface = phoneSize,
  Brightness brightness = Brightness.light,
  bool reducedMotion = false,
  bool online = false,
  bool seed = true,

  /// How much of the screen the keyboard is covering.
  ///
  /// Set on the `MediaQuery` the app is pumped under, not on `tester.view` —
  /// this harness builds its own `MediaQueryData`, so anything written to the
  /// view is discarded before a widget ever reads it, and a keyboard test
  /// that set it there would be testing nothing.
  double keyboardInset = 0,

  /// False stops at the first frame instead of running animations out. The
  /// brand intro routes away as soon as it settles, so a test that wants to
  /// see it has to stop before that.
  bool settle = true,

  /// Reuse the session record from an earlier pump — how a test restarts the
  /// app without wiping the phone.
  SessionStorage? session,
  AlmanacDatabase? storage,

  /// Runs the screens against the real [ApiAuthService] over this fake
  /// backend instead of the demo, the way every non-demo build does. The
  /// build flag that picks between them is overridden too, so the screens
  /// see the same answer the provider does.
  FakeAuthApi? api,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.reset);

  final db = storage ?? AlmanacDatabase.memory();
  if (seed) await DemoSeed(db, now: () => pinnedToday).ensureSeeded();
  final record = session ?? InMemorySessionStorage();

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => pinnedToday),
      if (!seed) seedProvider.overrideWith((ref) async {}),
      healthServiceProvider.overrideWithValue(
        _FixedHealth(online ? Reachability.online : Reachability.offline),
      ),
      sessionStorageProvider.overrideWithValue(record),
      demoAuthProvider.overrideWithValue(api == null),
      if (api != null)
        authServiceProvider.overrideWith(
          (ref) => ApiAuthService(
            api.dio(),
            ref.watch(sessionStorageProvider),
            now: () => pinnedToday,
          ),
        )
      else
        // The real demo service, with its cosmetic pause removed. The pause
        // exists so a person can see the busy state; a test that waited for
        // it would only be testing `Future.delayed`.
        authServiceProvider.overrideWith(
          (ref) => DemoAuthService(
            ref.watch(sessionStorageProvider),
            now: () => pinnedToday,
            settleDelay: Duration.zero,
          ),
        ),
    ],
  );

  final router = buildRouter(initialLocation: location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(
          size: surface,
          disableAnimations: reducedMotion,
          platformBrightness: brightness,
          viewInsets: EdgeInsets.only(bottom: keyboardInset),
        ),
        // The same app-root hook `AlmanacApp` runs, so a launch here reads
        // and refreshes the session exactly as a launch on a phone does.
        child: Consumer(
          builder: (context, ref, child) {
            keepSessionFresh(ref);
            return child!;
          },
          child: MaterialApp.router(
            routerConfig: router,
            theme: almanacLightTheme(),
            darkTheme: almanacDarkTheme(),
            themeMode: brightness == Brightness.dark
                ? ThemeMode.dark
                : ThemeMode.light,
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }

  addTearDown(() async {
    container.dispose();
    if (storage == null) await db.close();
  });

  return AuthHarness._(db, record, container);
}

/// Types into the field under [label], scrolling it into view first.
///
/// Finds the editable by walking up from the label to the field's own column,
/// so two fields whose labels share a word ("Password" and "Confirm password")
/// never resolve to the same input.
Future<void> enterField(WidgetTester tester, String label, String value) async {
  final field = find.ancestor(
    of: find.text(label),
    matching: find.byType(Column),
  );
  await tester.ensureVisible(field.first);
  await tester.pumpAndSettle();
  await tester.enterText(
    find.descendant(of: field.first, matching: find.byType(EditableText)).first,
    value,
  );
  await tester.pumpAndSettle();
}

/// Pumps a fixed number of frames instead of settling.
///
/// The verification screen animates for as long as it is on screen — the
/// caret blinks, which `app-forms.css` specifies and COMPONENTS.md repeats —
/// so `pumpAndSettle` there waits for an animation that never ends. Anything
/// that lands on that screen pumps frames instead.
Future<void> pumpBriefly(WidgetTester tester, {int frames = 10}) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 60));
  }
}

/// Taps a button by its word. Scrolls it into view first, because widget tests
/// render with a fixed-width test font that makes every page longer than it is
/// on a phone.
///
/// [settle] goes false when the tap lands on a screen that animates forever —
/// see [pumpBriefly].
Future<void> tapLabel(
  WidgetTester tester,
  String label, {
  bool settle = true,
}) async {
  final finder = find.text(label);
  await tester.ensureVisible(finder.first);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await pumpBriefly(tester);
  }
}

/// Taps the footer link whose link half reads [linkLabel].
///
/// `AuthFooterLink` paints its two halves as one `Text.rich`, so there is no
/// `Text` widget carrying the link words on their own and `find.text` misses
/// it entirely. Matching the widget by its `linkLabel` is what makes "Start
/// again" tappable from a test at all.
///
/// [settle] goes false on screens that animate forever — see [pumpBriefly].
Future<void> tapFooterLink(
  WidgetTester tester,
  String linkLabel, {
  bool settle = true,
}) async {
  final finder = find.byWidgetPredicate(
    (w) => w is AuthFooterLink && w.linkLabel == linkLabel,
  );
  await tester.ensureVisible(finder.first);
  await pumpBriefly(tester);
  await tester.tap(finder.first);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await pumpBriefly(tester);
  }
}

/// Whether the button carrying [label] is enabled.
///
/// Reads the `InkWell`'s callback rather than looking for a disabled colour:
/// the design expresses disabled as 45% opacity, and asserting on an opacity
/// would pass for a button that is dimmed and still tappable.
bool buttonEnabled(WidgetTester tester, String label) {
  final inkWell = find
      .ancestor(of: find.text(label), matching: find.byType(InkWell))
      .first;
  return tester.widget<InkWell>(inkWell).onTap != null;
}

/// A password that clears the policy, for tests that are about something else.
const goodPassphrase = 'three blind field mice';
