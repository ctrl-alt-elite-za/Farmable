/// Runs the real screens against a real database.
///
/// Nothing here mocks the repository. The screens are wired to an in-memory
/// SQLite database holding the real demo seed, with the clock pinned — so a
/// test that says "create an observation offline and it appears in the list"
/// is exercising the same code path the farmer does, including the storage.
/// A mocked repository would pass these tests with a broken database.
library;

import 'dart:async';

import 'package:almanac/app/providers.dart';
import 'package:almanac/app/router.dart';
import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/data/health_service.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

/// A fixed Sunday, matching the design's "Sunday, 20 September". Pinned so
/// assertions about overdue steps and "92 days" do not rot overnight.
final pinnedToday = DateTime(2026, 9, 20, 9, 42);

/// A phone, not a tablet. 390x844 is the design set's frame size, and it is
/// the width every overflow in this app will first appear at.
const phoneSize = Size(390, 844);

/// One of the three streams Zone Detail assembles itself from.
///
/// Named individually because each one has to be provable on its own: only the
/// section's failure was ever reported, and a test that failed all three at
/// once would not have noticed.
enum FailingStream { section, timeline, observations }

/// A stream that errors and then stays open, which is the shape the real
/// repository produces.
///
/// It matters that it does not close. A closed stream leaves Riverpod holding
/// an `AsyncError`; an open one that has errored leaves it holding an
/// `AsyncLoading` that carries the error, and that is the state a screen can
/// silently render as a spinner forever. Erroring with `Stream.error` would
/// close the stream and quietly test the easier of the two.
Stream<T> _storageIsDown<T>() {
  final controller = StreamController<T>();
  controller.addError(StateError('local storage would not answer'));
  return controller.stream;
}

class _FixedHealth implements HealthService {
  final Reachability result;

  const _FixedHealth(this.result);

  @override
  Future<Reachability> check() async => result;
}

class FarmHarness {
  final AlmanacDatabase db;
  final ProviderContainer container;

  FarmHarness._(this.db, this.container);

  Future<void> dispose() async {
    container.dispose();
    await db.close();
  }
}

/// Pumps the whole app — router, shell and all — at the given route.
///
/// [online] decides only the connectivity chip. The farm renders identically
/// either way, and a test that flips it and finds the dashboard changed has
/// found a real bug.
Future<FarmHarness> pumpFarmApp(
  WidgetTester tester, {
  String location = '/home',
  bool online = false,
  bool seed = true,
  Brightness brightness = Brightness.light,
  bool reducedMotion = false,

  /// Reuse storage from an earlier pump, which is how a test restarts the app
  /// without losing the phone. Everything above this line is rebuilt.
  AlmanacDatabase? storage,

  /// The logical screen. Defaults to the design set's frame; pass the 360dp
  /// floor to check the width the type scale was actually set for.
  Size surface = phoneSize,

  /// Which of Zone Detail's storage streams should fail instead of loading.
  ///
  /// The one thing that cannot be provoked from the database itself: a stream
  /// that errors before it has ever emitted, with no earlier value to fall
  /// back on. Nothing else here is substituted — the screens, the repository
  /// and the storage stay real.
  Set<FailingStream> failing = const {},

  /// Anything else a test substitutes — a camera, a photo folder. Appended
  /// after the harness's own, so it wins.
  List<Override> overrides = const [],
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.reset);

  final db = storage ?? AlmanacDatabase.memory();
  if (seed) {
    await DemoSeed(db, now: () => pinnedToday).ensureSeeded();
  }

  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => pinnedToday),
      // Home seeds on launch, so a test of the un-seeded state has to stop it
      // doing that as well as skipping the seed here.
      if (!seed) seedProvider.overrideWith((ref) async {}),
      healthServiceProvider.overrideWithValue(
        _FixedHealth(online ? Reachability.online : Reachability.offline),
      ),
      if (failing.contains(FailingStream.section))
        sectionProvider.overrideWith(
          (ref, id) => _storageIsDown<rec.SectionSummary?>(),
        ),
      if (failing.contains(FailingStream.timeline))
        timelineProvider.overrideWith(
          (ref, id) => _storageIsDown<List<rec.FarmTask>>(),
        ),
      if (failing.contains(FailingStream.observations))
        observationsProvider.overrideWith(
          (ref, id) => _storageIsDown<List<rec.Observation>>(),
        ),
      ...overrides,
    ],
  );

  final router = buildRouter();
  if (location != '/home') router.go(location);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(
          size: surface,
          disableAnimations: reducedMotion,
          platformBrightness: brightness,
        ),
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
  );
  await tester.pumpAndSettle();

  addTearDown(() async {
    container.dispose();
    if (storage == null) await db.close();
  });

  return FarmHarness._(db, container);
}

/// Every word this product must never use for a normal operating state.
///
/// Being offline, having records queued, and not having checked a section yet
/// are all Tuesdays. An app that calls any of them a failure teaches the
/// farmer that it is broken, and they stop trusting the parts that are not.
const forbiddenFailureWords = <String>[
  'error',
  'failed',
  'failure',
  'something went wrong',
  'unavailable',
  'no connection',
  'try again later',
];

/// Asserts that nothing currently on screen uses failure language.
void expectNoFailureLanguage(WidgetTester tester) {
  final texts = tester
      .widgetList<Text>(find.byType(Text))
      .map((t) => (t.data ?? t.textSpan?.toPlainText() ?? '').toLowerCase())
      .toList();

  for (final word in forbiddenFailureWords) {
    final offending = texts.where((t) => t.contains(word)).toList();
    expect(
      offending,
      isEmpty,
      reason:
          'offline and pending sync are calm states; found "$word" in '
          '$offending',
    );
  }
}

/// The screen's vertical scroller — the page itself, never the carousel.
Finder pageScrollable() => find.byWidgetPredicate(
  (w) =>
      w is Scrollable &&
      (w.axisDirection == AxisDirection.down ||
          w.axisDirection == AxisDirection.up),
);

/// Scrolls the page until [finder] matches something on screen.
///
/// Widget tests render with a fixed-width test font, which makes every string
/// far wider than the real face and pushes the page much longer than it is on
/// a phone. Scrolling rather than asserting on offscreen widgets keeps these
/// tests about what the farmer can reach, not about what happens to be built.
///
/// Rolled by hand rather than using `scrollUntilVisible`, which takes `.first`
/// of the finder on every iteration and throws before it has scrolled anywhere
/// when the finder starts out empty — which is the whole reason to scroll.
Future<void> revealOnPage(
  WidgetTester tester,
  Finder finder, {
  int maxScrolls = 40,
}) async {
  for (var i = 0; i < maxScrolls; i++) {
    if (finder.evaluate().isNotEmpty) {
      await tester.ensureVisible(finder.first);
      await tester.pumpAndSettle();
      return;
    }
    await tester.drag(pageScrollable().first, const Offset(0, -300));
    await tester.pumpAndSettle();
  }
  fail('Nothing matching $finder appeared after scrolling the page');
}
