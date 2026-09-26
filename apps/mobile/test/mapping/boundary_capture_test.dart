/// Pictures of every boundary screen state, for review and the PR.
///
/// Skipped unless `BOUNDARY_CAPTURE_DIR` names a folder to write into.
/// `BOUNDARY_CAPTURE_FONT` may name a .ttf to draw text with; without one,
/// text renders as the test font's boxes.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:almanac/data/local/seed.dart';
import 'package:almanac/data/mapping/recorded_walks.dart';
import 'package:almanac/domain/mapping/geometry.dart';
import 'package:almanac/domain/mapping/walk.dart';
import 'package:almanac/features/boundary/boundary_providers.dart';
import 'package:almanac/features/boundary/boundary_screen.dart';
import 'package:almanac/data/local/database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

const _path = '/farm/zone/${DemoSeed.northPlotId}/boundary';

class _Held implements WalkSource {
  final controller = StreamController<WalkSample>();
  @override
  bool get hasAr => true;
  @override
  String get description => 'A recorded walk, played back (test mode)';
  @override
  Stream<WalkSample> start() => controller.stream;
  @override
  Future<void> stop() async {}
}

void main() {
  final directory = Platform.environment['BOUNDARY_CAPTURE_DIR'];

  Future<void> fonts(WidgetTester tester) => tester.runAsync(() async {
    final icons = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(
        rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
      );
    await icons.load();
    final path = Platform.environment['BOUNDARY_CAPTURE_FONT'];
    if (path != null) {
      final bytes = await File(path).readAsBytes();
      final font = FontLoader('Inter')
        ..addFont(Future.value(ByteData.sublistView(bytes)));
      await font.load();
    }
  });

  Future<void> snap(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find
          .ancestor(
            of: find.byType(BoundaryScreen),
            matching: find.byType(RepaintBoundary),
          )
          .first,
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      await Directory(directory!).create(recursive: true);
      await File('$directory/$name.png')
          .writeAsBytes(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  testWidgets('capture every state', skip: directory == null, (tester) async {
    await fonts(tester);

    // Before, then walking with AR tracking lost.
    final held = _Held();
    var app = await pumpFarmApp(
      tester,
      location: _path,
      overrides: [walkSourceProvider.overrideWithValue(held)],
    );
    await tester.pumpAndSettle();
    await snap(tester, '1-before');
    await tester.tap(find.byKey(const Key('boundary-start')));
    await tester.pumpAndSettle();
    for (final s in recordedWalk(RecordedWalk.field).take(80)) {
      held.controller.add(s);
    }
    await tester.pump();
    await tester.pump();
    await tester.tap(find.byKey(const Key('boundary-mark-corner')));
    await snap(tester, '2-walking-tracking-lost');
    await tester.pumpWidget(const SizedBox());
    await app.dispose();

    for (final (name, walk) in [
      ('3-review-agree', RecordedWalk.field),
      ('4-review-drift-warning', RecordedWalk.drift),
      ('5-review-gps-only', RecordedWalk.gpsOnly),
    ]) {
      app = await pumpFarmApp(
        tester,
        location: _path,
        overrides: [
          walkSourceProvider.overrideWithValue(
            ReplayWalkSource(recordedWalk(walk), speed: 0),
          ),
        ],
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('boundary-start')));
      await snap(tester, name);
      await tester.pumpWidget(const SizedBox());
      await app.dispose();
    }

    // A crossed shape, refused.
    final db = AlmanacDatabase.memory();
    await DemoSeed(db, now: () => pinnedToday).ensureSeeded();
    await (db.update(
      db.sections,
    )..where((t) => t.id.equals(DemoSeed.northPlotId))).write(
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
    app = await pumpFarmApp(
      tester,
      location: '$_path?edit=1',
      storage: db,
      seed: false,
      overrides: [walkSourceProvider.overrideWithValue(_Held())],
    );
    await tester.pumpAndSettle();
    final a = tester.getCenter(find.byKey(const Key('boundary-corner-0')));
    final b = tester.getCenter(find.byKey(const Key('boundary-corner-1')));
    final c = tester.getCenter(find.byKey(const Key('boundary-corner-2')));
    await tester.dragFrom(a, (b + c) / 2 + (b - a) * 0.5 - a);
    await snap(tester, '6-review-crossing-refused');
    await tester.pumpWidget(const SizedBox());
    await app.dispose();
  });
}
