/// Walking, reviewing and saving a boundary (#15), end to end on the real
/// screens, repository and in-memory database. The only seam substituted is
/// where the walk's positions come from: a recorded walk played back, or a
/// scripted source for tracking loss and a refused permission.
library;

import 'dart:async';
import 'dart:convert';

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/data/mapping/recorded_walks.dart';
import 'package:almanac/domain/mapping/geometry.dart';
import 'package:almanac/domain/mapping/walk.dart';
import 'package:almanac/features/boundary/boundary_providers.dart';
import 'package:almanac/features/farm/farm_map_data.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

const _section = DemoSeed.northPlotId;
const _walkPath = '/farm/zone/$_section/boundary';

/// A source a test drives sample by sample, or fails on start.
class ScriptedWalkSource implements WalkSource {
  final WalkUnavailable? refuse;
  final controller = StreamController<WalkSample>();

  ScriptedWalkSource({this.refuse});

  @override
  bool get hasAr => true;

  @override
  String get description => 'Scripted walk';

  @override
  Stream<WalkSample> start() =>
      refuse == null ? controller.stream : Stream.error(refuse!);

  @override
  Future<void> stop() async {}
}

class _NoTiles extends TileProvider {
  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) =>
      throw StateError('the review map must not fetch tiles without consent');
}

List<Override> _seams(WalkSource source, {List<Override> extra = const []}) => [
  walkSourceProvider.overrideWithValue(source),
  farmMapTileProviderProvider.overrideWithValue(_NoTiles()),
  ...extra,
];

Future<void> _walk(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('boundary-start')));
  await tester.pumpAndSettle();
}

double _shownArea(WidgetTester tester) {
  final text = tester
      .widget<Text>(find.byKey(const Key('boundary-area')))
      .data!;
  final number = double.parse(text.replaceAll(RegExp(r'[^0-9.]'), ''));
  return text.endsWith('ha') ? number * 10000 : number;
}

String _agreement(WidgetTester tester) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byKey(const Key('boundary-agreement')),
        matching: find.byType(Text),
      ),
    )
    .map((t) => t.data)
    .join();

Future<void> _save(WidgetTester tester) async {
  final save = find.byKey(const Key('boundary-save'));
  await tester.ensureVisible(save);
  await tester.pumpAndSettle();
  await tester.tap(save);
  await tester.pumpAndSettle();
}

Future<Section> _stored(AlmanacDatabase db) =>
    (db.select(db.sections)..where((t) => t.id.equals(_section))).getSingle();

void main() {
  testWidgets('a recorded walk reviews within 1%, agrees, and saves offline '
      'with the change queued for sync', (tester) async {
    final app = await pumpFarmApp(
      tester,
      location: _walkPath,
      overrides: _seams(
        ReplayWalkSource(recordedWalk(RecordedWalk.field), speed: 0),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('boundary-source')), findsOneWidget);
    await _walk(tester);

    // The recording ran out, so review opened on its own.
    expect(find.text('Check the shape'), findsOneWidget);
    expect(
      disagreement(_shownArea(tester), recordedFieldAreaM2),
      lessThan(0.01),
    );
    expect(_agreement(tester), contains('agree'));
    expect(find.byKey(const Key('boundary-problem')), findsNothing);
    expect(find.byKey(const Key('boundary-soil')), findsOneWidget);

    final before = await _stored(app.db);
    await _save(tester);

    final after = await _stored(app.db);
    expect(after.areaSource, 'boundary_estimate');
    expect(after.version, before.version + 1);
    final ring = boundaryFromGeoJson(after.boundary)!;
    final saved = geodesicArea([
      for (final p in ring) GpsPoint(p.latitude, p.longitude),
    ]);
    expect(disagreement(saved, recordedFieldAreaM2), lessThan(0.01));
    expect(disagreement(double.parse(after.areaM2!), saved), lessThan(0.0001));

    final queued = await (app.db.select(
      app.db.syncMutations,
    )..where((t) => t.recordId.equals(_section))).get();
    expect(queued, hasLength(1));
    expect(queued.single.operation, 'update');
    expect(queued.single.syncedAt, isNull);
    final payload = jsonDecode(queued.single.payload!) as Map;
    expect((payload['boundary'] as Map)['type'], 'Polygon');
  });

  testWidgets('GPS that drifts more than 15% from AR is called out', (
    tester,
  ) async {
    final app = await pumpFarmApp(
      tester,
      location: _walkPath,
      overrides: _seams(
        ReplayWalkSource(recordedWalk(RecordedWalk.drift), speed: 0),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpAndSettle();
    await _walk(tester);

    expect(_agreement(tester), contains('more than the 15%'));
    // A warning, not a block: the farmer can still save.
    await _save(tester);
    expect((await _stored(app.db)).boundary, isNotNull);
  });

  testWidgets('a phone without AR walks with GPS only', (tester) async {
    final app = await pumpFarmApp(
      tester,
      location: _walkPath,
      overrides: _seams(
        ReplayWalkSource(recordedWalk(RecordedWalk.gpsOnly), speed: 0),
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpAndSettle();

    expect(find.textContaining('Each corner is good to a few'), findsOneWidget);
    await _walk(tester);
    expect(_agreement(tester), contains('GPS only'));
    expect(
      disagreement(_shownArea(tester), recordedFieldAreaM2),
      lessThan(0.08),
    );
  });

  testWidgets('losing AR tracking pauses AR and says so; GPS carries on', (
    tester,
  ) async {
    final source = ScriptedWalkSource();
    final app = await pumpFarmApp(
      tester,
      location: _walkPath,
      overrides: _seams(source),
    );
    addTearDown(app.dispose);
    await tester.pumpAndSettle();
    await _walk(tester);

    final samples = recordedWalk(RecordedWalk.field);
    for (final s in samples.take(60)) {
      source.controller.add(s);
    }
    await tester.pump();
    expect(find.byKey(const Key('boundary-tracking-lost')), findsNothing);

    for (final s in samples.skip(60).take(15)) {
      source.controller.add(s);
    }
    await tester.pump();
    expect(find.byKey(const Key('boundary-tracking-lost')), findsOneWidget);
    expect(find.text('Area so far'), findsOneWidget);

    for (final s in samples.skip(75)) {
      source.controller.add(s);
    }
    // Many samples at once: a second frame lets the last of them land.
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('boundary-tracking-lost')), findsNothing);

    await tester.tap(find.byKey(const Key('boundary-finish')));
    await tester.pumpAndSettle();
    expect(
      disagreement(_shownArea(tester), recordedFieldAreaM2),
      lessThan(0.01),
    );
  });

  testWidgets('finishing before the path encloses land keeps walking', (
    tester,
  ) async {
    final source = ScriptedWalkSource();
    final app = await pumpFarmApp(
      tester,
      location: _walkPath,
      overrides: _seams(source),
    );
    addTearDown(app.dispose);
    await tester.pumpAndSettle();
    await _walk(tester);

    await tester.tap(find.byKey(const Key('boundary-mark-corner')));
    await tester.pump();
    expect(find.textContaining('Wait for the first location fix'), findsOne);

    await tester.tap(find.byKey(const Key('boundary-finish')));
    await tester.pump();
    expect(find.textContaining('Keep walking'), findsOneWidget);
    expect(find.text('Check the shape'), findsNothing);
  });

  testWidgets('a refused location permission explains and opens Settings', (
    tester,
  ) async {
    var settingsOpened = 0;
    final app = await pumpFarmApp(
      tester,
      location: _walkPath,
      overrides: _seams(
        ScriptedWalkSource(
          refuse: const WalkUnavailable(
            'Location permission was refused.',
            permissionDenied: true,
          ),
        ),
        extra: [
          openAppSettingsProvider.overrideWithValue(() async {
            settingsOpened++;
            return true;
          }),
        ],
      ),
    );
    addTearDown(app.dispose);
    await tester.pumpAndSettle();
    await _walk(tester);

    expect(find.text('Location is needed to walk a boundary'), findsOneWidget);
    await tester.tap(find.byKey(const Key('boundary-open-settings')));
    await tester.pump();
    expect(settingsOpened, 1);
    expect((await _stored(app.db)).boundary, isNull);
  });

  group('editing a saved shape', () {
    Future<FarmHarness> pumpSaved(WidgetTester tester) async {
      final app = await pumpFarmApp(
        tester,
        location: '$_walkPath?edit=1',
        overrides: _seams(ScriptedWalkSource()),
      );
      addTearDown(app.dispose);
      await (app.db.update(
        app.db.sections,
      )..where((t) => t.id.equals(_section))).write(
        SectionsCompanion(
          boundary: Value(
            jsonEncode(
              ringToGeoJson(const [
                GpsPoint(-29.7400, 30.9700),
                GpsPoint(-29.7400, 30.9708),
                GpsPoint(-29.7407, 30.9708),
                GpsPoint(-29.7407, 30.9700),
              ]),
            ),
          ),
        ),
      );
      // Re-open now the shape is stored.
      app.container.invalidate(sectionBoundariesProvider);
      await tester.pumpAndSettle();
      return app;
    }

    testWidgets('dragging a corner across a side is refused with the reason, '
        'and Save stays off', (tester) async {
      final app = await pumpSaved(tester);
      // The flow opened before the shape was stored; open it again.
      await tester.pumpWidget(const SizedBox());
      final reopened = await pumpFarmApp(
        tester,
        location: '$_walkPath?edit=1',
        storage: app.db,
        seed: false,
        overrides: _seams(ScriptedWalkSource()),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('boundary-problem')), findsNothing);
      final before = _shownArea(tester);
      expect(before, greaterThan(0));

      final a = tester.getCenter(find.byKey(const Key('boundary-corner-0')));
      final b = tester.getCenter(find.byKey(const Key('boundary-corner-1')));
      final c = tester.getCenter(find.byKey(const Key('boundary-corner-2')));
      // Past the far side: the edge back to the first corner now crosses it.
      final target = (b + c) / 2 + (b - a) * 0.5;
      await tester.dragFrom(a, target - a);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('boundary-problem')), findsOneWidget);
      expect(find.textContaining('Two sides of the shape cross'), findsOne);
      expect(find.text('—'), findsOneWidget);

      final stored = (await _stored(app.db)).boundary;
      await _save(tester);
      expect((await _stored(app.db)).boundary, stored);
      expect(find.text('Check the shape'), findsOneWidget);

      // Dragging it back makes it valid again.
      final moved = tester.getCenter(
        find.byKey(const Key('boundary-corner-0')),
      );
      await tester.dragFrom(moved, a - moved);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('boundary-problem')), findsNothing);
      // Near where it began; a drag loses its first few pixels to the
      // gesture threshold, so not exactly.
      expect(disagreement(_shownArea(tester), before), lessThan(0.3));
      await _save(tester);
      expect((await _stored(app.db)).boundary, isNot(stored));
      reopened.container.dispose();
    });

    testWidgets('a corner can be added mid-side and removed again', (
      tester,
    ) async {
      final app = await pumpSaved(tester);
      await tester.pumpWidget(const SizedBox());
      final reopened = await pumpFarmApp(
        tester,
        location: '$_walkPath?edit=1',
        storage: app.db,
        seed: false,
        overrides: _seams(ScriptedWalkSource()),
      );
      await tester.pumpAndSettle();
      final area = _shownArea(tester);

      await tester.tap(find.byKey(const Key('boundary-add-0')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('boundary-corner-4')), findsOneWidget);
      expect(_shownArea(tester), closeTo(area, 1));

      await tester.longPress(find.byKey(const Key('boundary-corner-4')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('boundary-corner-4')), findsNothing);
      reopened.container.dispose();
    });
  });
}
