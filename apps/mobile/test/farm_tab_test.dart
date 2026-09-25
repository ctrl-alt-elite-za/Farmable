/// The Farm tab (#90): every section as a list and as a map, from the phone.
///
/// Runs the real screens against the real in-memory database and demo seed.
/// Two seams are substituted, both owned by the Farm tab: which sections have
/// a boundary — the farm snapshot carries none yet — and where map pictures
/// come from, so a test can count every request the map makes.
library;

import 'dart:typed_data';

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/features/farm/farm_map_data.dart';
import 'package:almanac/features/zone/zone_screen.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

import 'support/harness.dart';

/// Every tile the map asks for, answered with a transparent pixel and never
/// with a network request.
class RecordingTiles extends TileProvider {
  final requests = <TileCoordinates>[];

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    requests.add(coordinates);
    return MemoryImage(_transparentPixel);
  }
}

final _transparentPixel = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0B, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x60, 0x00, 0x02, 0x00,
  0x00, 0x05, 0x00, 0x01, 0x7A, 0x5E, 0xAB, 0x3F, 0x00, 0x00, 0x00, 0x00,
  0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

/// Two neighbouring plots near KwaMashu: Cabbage Field and Tomato Section
/// walked, North Plot and Spinach Beds not.
final walkedTwo = <String, List<LatLng>>{
  DemoSeed.cabbageFieldId: const [
    LatLng(-29.7400, 30.9700),
    LatLng(-29.7400, 30.9708),
    LatLng(-29.7407, 30.9708),
    LatLng(-29.7407, 30.9700),
  ],
  DemoSeed.tomatoSectionId: const [
    LatLng(-29.7400, 30.9710),
    LatLng(-29.7400, 30.9717),
    LatLng(-29.7407, 30.9717),
    LatLng(-29.7407, 30.9710),
  ],
};

List<Override> mapSeams(
  RecordingTiles tiles, {
  Map<String, List<LatLng>> boundaries = const {},
}) => [
  farmMapTileProviderProvider.overrideWithValue(tiles),
  sectionBoundariesProvider.overrideWithValue(boundaries),
];

Future<void> removeSections(AlmanacDatabase db, List<String> ids) async {
  await (db.update(db.sections)..where((t) => t.id.isIn(ids))).write(
    SectionsCompanion(deletedAt: Value(pinnedToday)),
  );
}

Future<void> addSections(AlmanacDatabase db, int count) async {
  for (var i = 1; i <= count; i++) {
    await db
        .into(db.sections)
        .insert(
          SectionsCompanion.insert(
            id: 'extra-section-$i',
            farmId: DemoSeed.farmId,
            ownerId: DemoSeed.ownerId,
            name: 'Extra Bed $i',
            areaM2: const Value('250.00'),
            createdAt: pinnedToday,
            updatedAt: pinnedToday,
          ),
        );
  }
}

const allFour = [
  'Cabbage Field',
  'Tomato Section',
  'North Plot',
  'Spinach Beds',
];

/// Scrolls [finder] to the middle of the page and taps it — clear of the
/// navigation island, which floats over the foot of every screen.
Future<void> tapOnPage(WidgetTester tester, Finder finder) async {
  await revealOnPage(tester, finder);
  await Scrollable.ensureVisible(tester.element(finder.first), alignment: 0.5);
  await tester.pumpAndSettle();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

/// Asserts that nothing on screen overflowed while it was built.
void expectNoOverflow(WidgetTester tester) {
  final error = tester.takeException();
  expect(error, isNull, reason: 'the layout overflowed: $error');
}

void main() {
  group('sections mode', () {
    testWidgets('lists every section with its crop, area, status and next '
        'task — from the phone, with no signal', (tester) async {
      await pumpFarmApp(tester, location: '/farm');

      expect(find.text('Siyakhula Farm'), findsOneWidget);
      expect(find.text('2.4 ha · 4 sections · KwaMashu'), findsOneWidget);
      for (final name in allFour) {
        await revealOnPage(tester, find.text(name));
      }
      await revealOnPage(tester, find.text('Cabbage Field'));
      expect(find.text('Cabbage · 0.6 ha'), findsOneWidget);
      expect(find.text('Empty · 0.7 ha'), findsOneWidget);
      expect(find.text('Not planted'), findsWidgets);
      expect(find.textContaining('Next: Weed second row'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expectNoFailureLanguage(tester);
    });

    testWidgets('many sections: every one is reachable', (tester) async {
      final app = await pumpFarmApp(tester, location: '/farm');
      await addSections(app.db, 8);
      await tester.pumpAndSettle();

      expect(find.text('2.6 ha · 12 sections · KwaMashu'), findsOneWidget);
      for (final name in [
        ...allFour,
        for (var i = 1; i <= 8; i++) 'Extra Bed $i',
      ]) {
        await revealOnPage(tester, find.text(name));
      }
      await revealOnPage(tester, find.text('Add section'));
    });

    testWidgets('one section', (tester) async {
      final app = await pumpFarmApp(tester, location: '/farm');
      await removeSections(app.db, [
        DemoSeed.tomatoSectionId,
        DemoSeed.northPlotId,
        DemoSeed.spinachBedsId,
      ]);
      await tester.pumpAndSettle();

      expect(find.text('0.6 ha · 1 section · KwaMashu'), findsOneWidget);
      expect(find.text('Cabbage Field'), findsOneWidget);
      expect(find.text('Tomato Section'), findsNothing);
      expect(find.text('Add section'), findsOneWidget);
    });

    testWidgets('no sections: says what a section is, and that adding one '
        'is coming — never as a failure', (tester) async {
      final app = await pumpFarmApp(tester, location: '/farm');
      await removeSections(app.db, [
        DemoSeed.cabbageFieldId,
        DemoSeed.tomatoSectionId,
        DemoSeed.northPlotId,
        DemoSeed.spinachBedsId,
      ]);
      await tester.pumpAndSettle();

      expect(find.text('Your farm has no sections yet'), findsOneWidget);
      expect(find.text('0 sections · KwaMashu'), findsOneWidget);
      await tapOnPage(tester, find.text('Add a section'));

      expect(find.text('Adding a section is coming'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('no farm on the phone is a state, not an error', (
      tester,
    ) async {
      await pumpFarmApp(tester, location: '/farm', seed: false);

      expect(find.text('Set up your farm'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('tapping a section opens its Zone Detail', (tester) async {
      await pumpFarmApp(tester, location: '/farm');
      await tapOnPage(tester, find.text('Spinach Beds'));

      final zone = tester.widget<ZoneScreen>(find.byType(ZoneScreen));
      expect(zone.sectionId, DemoSeed.spinachBedsId);
    });

    testWidgets('"Add section" says it is coming', (tester) async {
      await pumpFarmApp(tester, location: '/farm');
      await tapOnPage(tester, find.text('Add section'));

      expect(find.text('Adding a section is coming'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });

    testWidgets('queued work and no signal are calm facts', (tester) async {
      await pumpFarmApp(tester, location: '/farm');

      expect(find.text('3 changes waiting'), findsOneWidget);
      expectNoFailureLanguage(tester);
    });
  });

  group('map mode', () {
    testWidgets('with nothing walked, every section is listed as not mapped '
        'yet and nothing is fetched', (tester) async {
      final tiles = RecordingTiles();
      await pumpFarmApp(
        tester,
        location: '/farm?view=map',
        overrides: mapSeams(tiles),
      );

      expect(find.text('No boundaries walked yet'), findsOneWidget);
      expect(find.byType(FlutterMap), findsNothing);
      for (final name in allFour) {
        await revealOnPage(tester, find.text(name));
      }
      expect(find.text('Not mapped yet'), findsWidgets);
      expect(find.text('4 sections with no boundary'), findsOneWidget);
      expect(tiles.requests, isEmpty);
      expectNoFailureLanguage(tester);
    });

    testWidgets('draws walked sections and lists the rest as not mapped yet', (
      tester,
    ) async {
      final tiles = RecordingTiles();
      await pumpFarmApp(
        tester,
        location: '/farm?view=map',
        overrides: mapSeams(tiles, boundaries: walkedTwo),
      );

      final map = find.byKey(const Key('farm-map'));
      expect(map, findsOneWidget);
      final polygons = tester.widget<PolygonLayer<String>>(
        find.byType(PolygonLayer<String>),
      );
      expect(
        polygons.polygons.map((p) => p.hitValue),
        unorderedEquals([DemoSeed.cabbageFieldId, DemoSeed.tomatoSectionId]),
      );
      expect(
        find.descendant(of: map, matching: find.text('Cabbage Field')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: map, matching: find.text('North Plot')),
        findsNothing,
      );
      expect(find.text('Offline map'), findsOneWidget);

      await revealOnPage(tester, find.text('2 sections with no boundary'));
      expect(
        find.byKey(const ValueKey('unmapped-${DemoSeed.northPlotId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('unmapped-${DemoSeed.spinachBedsId}')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('unmapped-${DemoSeed.cabbageFieldId}')),
        findsNothing,
      );
    });

    testWidgets('no map picture is fetched before the farmer says yes', (
      tester,
    ) async {
      final tiles = RecordingTiles();
      await pumpFarmApp(
        tester,
        location: '/farm?view=map',
        overrides: mapSeams(tiles, boundaries: walkedTwo),
      );

      expect(find.byType(TileLayer), findsNothing);
      expect(tiles.requests, isEmpty);
      expect(find.textContaining('roughly where your farm is'), findsOneWidget);
      expect(find.text('© OpenStreetMap contributors'), findsNothing);

      await tapOnPage(tester, find.text('Show street map'));

      expect(find.byType(TileLayer), findsOneWidget);
      expect(tiles.requests, isNotEmpty);
      expect(find.text('© OpenStreetMap contributors'), findsOneWidget);

      await tapOnPage(tester, find.text('Hide street map'));
      expect(find.byType(TileLayer), findsNothing);
    });

    testWidgets('tapping a shape raises its card; "Open section" opens Zone '
        'Detail', (tester) async {
      await pumpFarmApp(
        tester,
        location: '/farm?view=map',
        overrides: mapSeams(RecordingTiles(), boundaries: walkedTwo),
      );

      await tester.tap(
        find.descendant(
          of: find.byKey(const Key('farm-map')),
          matching: find.text('Tomato Section'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('0.5 ha · tapped on map'), findsOneWidget);
      expect(find.text('Needs attention'), findsOneWidget);
      // Choosing on the map does not navigate by itself.
      expect(find.byType(ZoneScreen), findsNothing);

      await tapOnPage(tester, find.text('Open section'));
      final zone = tester.widget<ZoneScreen>(find.byType(ZoneScreen));
      expect(zone.sectionId, DemoSeed.tomatoSectionId);
    });

    testWidgets('a section that is not mapped still opens', (tester) async {
      await pumpFarmApp(
        tester,
        location: '/farm?view=map',
        overrides: mapSeams(RecordingTiles(), boundaries: walkedTwo),
      );
      final row = find.byKey(
        const ValueKey('unmapped-${DemoSeed.northPlotId}'),
      );
      await tapOnPage(tester, row);

      final zone = tester.widget<ZoneScreen>(find.byType(ZoneScreen));
      expect(zone.sectionId, DemoSeed.northPlotId);
    });

    testWidgets('the segmented control switches between the two modes', (
      tester,
    ) async {
      await pumpFarmApp(
        tester,
        location: '/farm',
        overrides: mapSeams(RecordingTiles()),
      );
      await revealOnPage(tester, find.text('Add section'));

      await tester.drag(pageScrollable().first, const Offset(0, 3000));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Map'));
      await tester.pumpAndSettle();
      expect(find.text('No boundaries walked yet'), findsOneWidget);

      await tester.tap(find.text('Sections'));
      await tester.pumpAndSettle();
      expect(find.text('No boundaries walked yet'), findsNothing);
    });
  });

  group('full farm map', () {
    testWidgets('draws walked sections, names the rest, and fetches nothing '
        'until asked', (tester) async {
      final tiles = RecordingTiles();
      await pumpFarmApp(
        tester,
        location: '/farm/map',
        overrides: mapSeams(tiles, boundaries: walkedTwo),
      );

      expect(find.byKey(const Key('farm-map')), findsOneWidget);
      expect(find.text('Not mapped yet · 2 sections'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('unmapped-${DemoSeed.northPlotId}')),
        findsOneWidget,
      );
      expect(find.text('2.4 ha'), findsOneWidget);
      expect(find.text('Offline map'), findsOneWidget);
      expect(find.byType(TileLayer), findsNothing);
      expect(tiles.requests, isEmpty);

      await tester.tap(find.byTooltip('Map layers'));
      await tester.pumpAndSettle();
      expect(tiles.requests, isEmpty, reason: 'explaining is not consenting');
      await tester.tap(find.text('Show street map'));
      await tester.pumpAndSettle();

      expect(find.byType(TileLayer), findsOneWidget);
      expect(tiles.requests, isNotEmpty);
    });

    testWidgets('with nothing walked it says so and lists every section', (
      tester,
    ) async {
      final tiles = RecordingTiles();
      await pumpFarmApp(
        tester,
        location: '/farm/map',
        overrides: mapSeams(tiles),
      );

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('No boundaries walked yet'), findsOneWidget);
      expect(find.text('Not mapped yet · 4 sections'), findsOneWidget);
      expect(tiles.requests, isEmpty);
      expectNoFailureLanguage(tester);
    });

    testWidgets('an unmapped section opens its Zone Detail', (tester) async {
      await pumpFarmApp(
        tester,
        location: '/farm/map',
        overrides: mapSeams(RecordingTiles(), boundaries: walkedTwo),
      );
      await tester.tap(
        find.byKey(const ValueKey('unmapped-${DemoSeed.spinachBedsId}')),
      );
      await tester.pumpAndSettle();

      final zone = tester.widget<ZoneScreen>(find.byType(ZoneScreen));
      expect(zone.sectionId, DemoSeed.spinachBedsId);
    });
  });

  group('light, dark and large text', () {
    for (final brightness in Brightness.values) {
      for (final scale in [1.0, 2.0]) {
        final label = '${brightness.name}, text ×$scale';

        testWidgets('sections mode lays out ($label)', (tester) async {
          await pumpFarmApp(
            tester,
            location: '/farm',
            brightness: brightness,
            textScale: scale,
            surface: const Size(360, 740),
          );
          expectNoOverflow(tester);
          await revealOnPage(tester, find.text('Add section'));
          expectNoOverflow(tester);
        });

        testWidgets('map mode lays out ($label)', (tester) async {
          await pumpFarmApp(
            tester,
            location: '/farm?view=map',
            brightness: brightness,
            textScale: scale,
            surface: const Size(360, 740),
            overrides: mapSeams(RecordingTiles(), boundaries: walkedTwo),
          );
          expectNoOverflow(tester);
          await tapOnPage(
            tester,
            find.descendant(
              of: find.byKey(const Key('farm-map')),
              matching: find.text('Cabbage Field'),
            ),
          );
          expectNoOverflow(tester);
          await revealOnPage(tester, find.text('2 sections with no boundary'));
          expectNoOverflow(tester);
        });

        testWidgets('full map lays out ($label)', (tester) async {
          await pumpFarmApp(
            tester,
            location: '/farm/map',
            brightness: brightness,
            textScale: scale,
            surface: const Size(360, 740),
            overrides: mapSeams(RecordingTiles(), boundaries: walkedTwo),
          );
          expectNoOverflow(tester);
        });
      }
    }
  });

  group('boundaryFrom', () {
    test('reads GeoJSON [longitude, latitude] pairs', () {
      expect(
        boundaryFrom([
          [30.97, -29.74],
          [30.98, -29.74],
          [30.98, -29.75],
          [30.97, -29.74],
        ]),
        const [
          LatLng(-29.74, 30.97),
          LatLng(-29.74, 30.98),
          LatLng(-29.75, 30.98),
        ],
      );
    });

    test('a line or a dot is not mapped land', () {
      expect(boundaryFrom(null), isNull);
      expect(
        boundaryFrom([
          [30.97, -29.74],
          [30.98, -29.74],
          [30.97, -29.74],
        ]),
        isNull,
      );
    });
  });
}
