/// The farm health overview (#92, design screen 25), asserted as behaviour.
///
/// The seeded farm covers "mixed" and the taps into Zone Detail through the
/// real router and storage. The other states — every section healthy, nothing
/// written down, checks weeks old with no signal — are not in the seed, so
/// those tests hand the screen a farm snapshot directly through the same
/// `farmProvider` it reads in the app.
library;

import 'package:almanac/app/providers.dart';
import 'package:almanac/app/router.dart';
import 'package:almanac/app/theme/app_theme.dart';
import 'package:almanac/data/health_service.dart';
import 'package:almanac/data/local/database.dart' show AlmanacDatabase;
import 'package:almanac/domain/farm_records.dart';
import 'package:almanac/domain/money.dart';
import 'package:almanac/features/health/health_screen.dart';
import 'package:almanac/features/zone/zone_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

void main() {
  group('mixed health, from the seeded farm', () {
    testWidgets('lists every section worst first, with the reason', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/health');

      expect(find.byType(HealthScreen), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // Tomato Section needs attention and leads; the two on-track sections
      // follow, the longer-unchecked first; North Plot, with nothing growing,
      // comes last.
      _expectInOrder(tester, [
        'Tomato Section',
        // Both on track: the older check first.
        'Spinach Beds',
        'Cabbage Field',
        'North Plot',
      ]);

      // The reason is the observation's own words, not only a state.
      expect(
        find.text(
          'Curling and purple veins on the lower leaves of the middle rows.',
        ),
        findsWidgets,
      );
      expect(find.text('3 days ago'), findsOneWidget);
      expect(find.text('Nothing growing yet'), findsOneWidget);
      expect(find.text('Not planted'), findsOneWidget);
      expect(
        find.text('1 of 3 planted sections needs a look.'),
        findsOneWidget,
      );
      expectNoFailureLanguage(tester);
    });

    testWidgets('tapping a section opens its Zone Detail', (tester) async {
      await pumpFarmApp(tester, location: '/health');

      await tester.tap(find.text('Spinach Beds'));
      await tester.pumpAndSettle();

      final zone = tester.widget<ZoneScreen>(find.byType(ZoneScreen));
      expect(zone.sectionId, isNotEmpty);
      expect(find.text('Spinach Beds'), findsWidgets);
    });

    testWidgets('"Open" on a section that needs a look goes to that section', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/health');

      await revealOnPage(tester, find.text('Open Tomato Section'));
      await tester.tap(find.text('Open Tomato Section'));
      await tester.pumpAndSettle();

      expect(find.byType(ZoneScreen), findsOneWidget);
      expect(find.text('Tomato Section'), findsWidgets);
    });

    // Tomato Section holds two observations: "Leaf curl" (the latest, needs
    // attention) and an older "Routine check" (on track). The link has to
    // open the one the state was read from, not merely one from the section.
    testWidgets('tapping the reason opens that exact observation', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/health');

      await tester.tap(
        find.bySemanticsLabel(RegExp('^Open the note on Tomato Section')),
      );
      await tester.pumpAndSettle();

      // The observation's own sheet, over the overview — not Zone Detail.
      expect(find.text('Leaf curl'), findsOneWidget);
      expect(find.text('Routine check'), findsNothing);
      expect(find.byType(ZoneScreen), findsNothing);

      // And Edit opens that record's own words.
      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      expect(find.text('Change this observation'), findsOneWidget);
      expect(
        find.widgetWithText(
          TextField,
          'Curling and purple veins on the lower leaves of the middle rows.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('"See the note" acts on the observation behind the state', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/health');

      await revealOnPage(tester, find.text('See the note'));
      await tester.tap(find.text('See the note'));
      await tester.pumpAndSettle();
      expect(find.text('Leaf curl'), findsOneWidget);

      // Deleting it withdraws exactly that record: Tomato Section falls back
      // to the older on-track check, and nothing needs a look any more.
      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').last);
      await tester.pumpAndSettle();

      expect(find.byType(HealthScreen), findsOneWidget);
      expect(find.text('Needs a look'), findsNothing);
      await revealOnPage(
        tester,
        find.text('Staking finished. Plants holding well after the wind.'),
      );
    });

    testWidgets('a section with nothing written down has no note to open', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/health');

      expect(
        find.bySemanticsLabel(RegExp('^Open the note on North Plot')),
        findsNothing,
      );
      expect(
        find.bySemanticsLabel(RegExp('^Open the note on Tomato Section')),
        findsOneWidget,
      );
    });

    testWidgets('Home\'s "Review health" opens the overview', (tester) async {
      await pumpFarmApp(tester);

      await revealOnPage(tester, find.text('Review health'));
      await tester.tap(find.text('Review health'));
      await tester.pumpAndSettle();

      expect(find.byType(HealthScreen), findsOneWidget);
    });

    testWidgets('renders in dark mode', (tester) async {
      await pumpFarmApp(
        tester,
        location: '/health',
        brightness: Brightness.dark,
      );

      expect(find.text('Tomato Section'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });

  group('built from a given farm', () {
    testWidgets('all healthy', (tester) async {
      await _pumpHealth(
        tester,
        _farm([
          _section('Cabbage Field', health: 'on_track', daysAgo: 0),
          _section('Spinach Beds', health: 'on_track', daysAgo: 2),
        ]),
      );

      expect(find.text('On track'), findsNWidgets(3));
      expect(find.text('Needs a look'), findsNothing);
      expect(find.text('Every checked section is on track.'), findsOneWidget);
      expect(find.text('Last checked today'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('mixed: action required outranks needs attention', (
      tester,
    ) async {
      await _pumpHealth(
        tester,
        _farm([
          _section('Alpha Bed', health: 'on_track', daysAgo: 1),
          _section('Bravo Bed', health: 'needs_attention', daysAgo: 1),
          _section('Charlie Bed', health: null),
          _section('Delta Bed', health: 'action_required', daysAgo: 2),
          _section('Echo Bed', health: null, planted: false),
        ]),
      );

      _expectInOrder(tester, [
        'Delta Bed',
        'Bravo Bed',
        // Planted and never checked ranks above a section known to be fine.
        'Charlie Bed',
        'Alpha Bed',
        'Echo Bed',
      ]);
      expect(find.text('2 of 4 planted sections need a look.'), findsOneWidget);
    });

    testWidgets('no observations yet reads as a start, not a gap', (
      tester,
    ) async {
      await _pumpHealth(
        tester,
        _farm([
          _section('Cabbage Field', health: null),
          _section('North Plot', health: null, planted: false),
        ]),
      );

      expect(find.text('Nothing checked yet'), findsOneWidget);
      // Once for the farm, once for the planted section.
      expect(find.text('Not checked yet'), findsNWidgets(2));
      expect(find.text('Nothing written down yet'), findsOneWidget);
      // The gauge shows a dash, never a made-up zero.
      expect(find.text('—'), findsOneWidget);
      expect(find.text('0'), findsNothing);
      // Scans are said to be coming, plainly.
      await revealOnPage(tester, find.text('Crop scans are coming'));
      expectNoFailureLanguage(tester);
    });

    testWidgets('offline with stale data: works, and says how old it is', (
      tester,
    ) async {
      await _pumpHealth(
        tester,
        _farm([
          _section('Cabbage Field', health: 'on_track', daysAgo: 20),
          _section('Tomato Section', health: 'needs_attention', daysAgo: 12),
        ]),
        online: false,
      );

      expect(find.text('Offline'), findsOneWidget);
      expect(find.text('Last checked 12 days ago'), findsOneWidget);
      expect(find.text('20 days ago · may have changed since'), findsOneWidget);
      expect(find.text('12 days ago · may have changed since'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('a recent check is not called stale', (tester) async {
      await _pumpHealth(
        tester,
        _farm([_section('Cabbage Field', health: 'on_track', daysAgo: 7)]),
      );

      expect(find.text('7 days ago'), findsOneWidget);
      expect(find.textContaining('may have changed'), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('large text lays out without overflow (${brightness.name})', (
        tester,
      ) async {
        await _pumpHealth(
          tester,
          _farm([
            _section('Cabbage Field', health: 'on_track', daysAgo: 20),
            _section('Tomato Section', health: 'needs_attention', daysAgo: 3),
            _section('Spinach Beds', health: 'action_required', daysAgo: 1),
            _section('North Plot', health: null, planted: false),
          ]),
          textScale: 1.5,
          brightness: brightness,
          surface: const Size(360, 780),
        );

        // An overflow is reported as an exception by the test binding.
        expect(tester.takeException(), isNull);
        await revealOnPage(tester, find.text('Crop scans are coming'));
        expect(tester.takeException(), isNull);
      });
    }
  });
}

/// Asserts the section names appear top to bottom in [names]' order.
void _expectInOrder(WidgetTester tester, List<String> names) {
  final ys = [for (final n in names) tester.getTopLeft(find.text(n).first).dy];
  for (var i = 1; i < ys.length; i++) {
    expect(
      ys[i],
      greaterThan(ys[i - 1]),
      reason: '${names[i]} should come after ${names[i - 1]}',
    );
  }
}

Future<void> _pumpHealth(
  WidgetTester tester,
  FarmSnapshot farm, {
  bool online = true,
  double textScale = 1,
  Brightness brightness = Brightness.light,
  Size surface = phoneSize,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = surface;
  addTearDown(tester.view.reset);

  final db = AlmanacDatabase.memory();
  final container = ProviderContainer(
    overrides: [
      databaseProvider.overrideWithValue(db),
      clockProvider.overrideWithValue(() => pinnedToday),
      seedProvider.overrideWith((ref) async {}),
      farmProvider.overrideWith((ref) => Stream.value(farm)),
      reachabilityProvider.overrideWith(
        (ref) async => online ? Reachability.online : Reachability.offline,
      ),
    ],
  );
  addTearDown(() async {
    container.dispose();
    await db.close();
  });

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MediaQuery(
        data: MediaQueryData(
          size: surface,
          platformBrightness: brightness,
          textScaler: TextScaler.linear(textScale),
        ),
        child: MaterialApp.router(
          routerConfig: buildRouter(initialLocation: '/health'),
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
}

FarmSnapshot _farm(List<SectionSummary> sections) => FarmSnapshot(
  farm: const Farm(
    id: 'farm-1',
    ownerId: 'owner-1',
    name: 'Test Farm',
    locality: null,
    version: 1,
    syncState: SyncState.synced,
  ),
  farmerFirstName: 'Sipho',
  sections: sections,
  upcoming: const [],
  pendingChanges: 0,
);

var _ids = 0;

/// A section. [health] null means nothing has been written down there.
SectionSummary _section(
  String name, {
  required String? health,
  int daysAgo = 0,
  bool planted = true,
}) {
  final id = 'section-${_ids++}';
  final state = HealthState.parse(health);
  return SectionSummary(
    section: FarmSection(
      id: id,
      farmId: 'farm-1',
      name: name,
      areaM2: const DecimalString('1000.00'),
      version: 1,
      syncState: SyncState.synced,
    ),
    planting: planted
        ? Planting(
            id: 'planting-$id',
            sectionId: id,
            crop: 'cabbage',
            variety: null,
            plantedOn: pinnedToday.subtract(const Duration(days: 30)),
            isCurrent: true,
          )
        : null,
    projection: null,
    latestObservation: health == null
        ? null
        : Observation(
            id: 'obs-$id',
            sectionId: id,
            type: 'general',
            note: 'Note on $name.',
            healthStatus: state,
            actionTaken: null,
            createdByVoice: false,
            createdAt: pinnedToday.subtract(Duration(days: daysAgo)),
            syncState: SyncState.synced,
            healthScore: switch (state) {
              HealthState.onTrack => 88,
              HealthState.needsAttention => 60,
              HealthState.actionRequired => 30,
              HealthState.unknown => null,
            },
          ),
    nextTask: null,
    spentSoFar: const Cents(0),
    pendingChanges: 0,
  );
}
