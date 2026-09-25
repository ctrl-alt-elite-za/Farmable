/// What the farmer sees of a record's journey to the server, on the real
/// Zone Detail screen over real storage: queued, sending, sent, stopped with
/// a way to try again, and changed elsewhere. Plus the photo on the form.
library;

import 'dart:io';

import 'package:almanac/app/providers.dart';
import 'package:almanac/data/device/photo_capture.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/offline_photos.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:almanac/features/zone/zone_view_model.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../support/harness.dart';

const _cabbage = '/farm/zone/${DemoSeed.cabbageFieldId}';

class _FakeCamera implements PhotoTaker {
  _FakeCamera(this.file);
  final File file;

  @override
  Future<CapturedPhoto?> take(BuildContext context) async =>
      CapturedPhoto(file.uri, 'image/jpeg');
}

void main() {
  Future<String> seedObservation(AlmanacDatabase db) async =>
      (await LocalFarmRepository(
            db,
            now: () => pinnedToday,
            ownerId: DemoSeed.ownerId,
          ).createObservation(
            sectionId: DemoSeed.cabbageFieldId,
            type: 'Stem borer',
            note: 'Holes in three stems',
            healthStatus: rec.HealthState.needsAttention,
          ))
          .id;

  Future<void> setDelivery(AlmanacDatabase db, String recordId, String state) =>
      (db.update(
        db.syncMutations,
      )..where((t) => t.recordId.equals(recordId))).write(
        SyncMutationsCompanion(
          deliveryState: Value(state),
          syncedAt: Value(state == 'synced' ? pinnedToday : null),
          errorCode: Value(state == 'failed' ? 'validation_error' : null),
        ),
      );

  Finder chip(String state) =>
      find.bySemanticsIdentifier('record-delivery-$state');

  testWidgets(
    'each delivery state is said in words, and only a stopped send offers "Try again"',
    (tester) async {
      final db = AlmanacDatabase.memory();
      addTearDown(db.close);
      await DemoSeed(db, now: () => pinnedToday).ensureSeeded();
      final id = await seedObservation(db);
      await pumpFarmApp(tester, location: _cabbage, storage: db);
      await revealOnPage(tester, find.text('Holes in three stems'));

      expect(chip('queued'), findsOneWidget);
      expect(find.text('1 change waiting'), findsWidgets);

      await setDelivery(db, id, 'syncing');
      await tester.pumpAndSettle();
      expect(chip('sending'), findsOneWidget);
      expect(find.text('Sending'), findsOneWidget);

      await setDelivery(db, id, 'conflict');
      await tester.pumpAndSettle();
      expect(chip('conflict'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);

      await setDelivery(db, id, 'failed');
      await tester.pumpAndSettle();
      expect(chip('failed'), findsOneWidget);
      expect(find.text('Not sent yet'), findsOneWidget);
      expectNoFailureLanguage(tester);

      await tester.tap(find.text('Try again'));
      await tester.pumpAndSettle();
      expect(chip('queued'), findsOneWidget);
      expect(find.text('Try again'), findsNothing);
      final row = await db
          .select(db.syncMutations)
          .get()
          .then((rows) => rows.singleWhere((r) => r.recordId == id));
      expect(row.deliveryState, 'pending');
      expect(row.budgetCount, 0);

      await setDelivery(db, id, 'synced');
      await tester.pumpAndSettle();
      expect(chip('sent'), findsOneWidget);
      expect(find.text('Sent'), findsOneWidget);
    },
  );

  testWidgets('a photo taken on the form is queued ahead of its observation', (
    tester,
  ) async {
    final root = await tester.runAsync(
      () => Directory.systemTemp.createTemp('almanac_form_'),
    );
    addTearDown(() => root!.delete(recursive: true));
    final camera = File('${root!.path}/shot.jpg');
    await tester.runAsync(
      () => camera.writeAsBytes([255, 216, 255, 224, ...List.filled(500, 1)]),
    );

    final harness = await pumpFarmApp(
      tester,
      location: _cabbage,
      overrides: [
        photoTakerProvider.overrideWithValue(_FakeCamera(camera)),
        photoStoreProvider.overrideWithValue(
          ({required ownerId, required farmId}) async => OfflinePhotos(
            Directory('${root.path}/photos'),
            ownerId: ownerId,
            farmId: farmId,
          ),
        ),
      ],
    );
    await revealOnPage(tester, find.text('Recent observations'));
    await tester.tap(find.text('Add').last);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), 'Aphids');
    await tester.enterText(find.byType(TextField).at(1), 'Under the leaves');
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('observation-add-photo')));
    await tester.pumpAndSettle();
    expect(find.text('Photo added'), findsOneWidget);

    await tester.tap(find.text('Save'));
    // The photo is copied with real file IO, which the test clock cannot
    // finish on its own.
    for (var i = 0; i < 200; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump();
      if (find.text('Photo added').evaluate().isEmpty) break;
    }
    await tester.pumpAndSettle();
    await revealOnPage(tester, find.textContaining('Under the leaves'));

    final db = harness.db;
    final photo = await db.select(db.localPhotos).getSingle();
    final rows = await db.select(db.syncMutations).get();
    final media = rows.singleWhere((r) => r.recordType == 'media');
    final observation = rows.lastWhere((r) => r.recordType == 'observation');
    expect(media.recordId, photo.id);
    expect(observation.dependencyId, media.mutationId);
    expect(media.ownerId, DemoSeed.ownerId);
    expect(
      await tester.runAsync(
        () => File('${root.path}/photos/${photo.relativePath}').exists(),
      ),
      isTrue,
    );
  });

  testWidgets(
    'a timeline step and the section itself say where they are, and a '
    'stopped send of either can be tried again',
    (tester) async {
      final db = AlmanacDatabase.memory();
      addTearDown(db.close);
      await DemoSeed(db, now: () => pinnedToday).ensureSeeded();
      final repo = LocalFarmRepository(
        db,
        now: () => pinnedToday,
        ownerId: DemoSeed.ownerId,
      );
      final task = await repo.createTask(
        sectionId: DemoSeed.cabbageFieldId,
        title: 'Check the drip line',
        dueDate: pinnedToday.add(const Duration(days: 3)),
      );
      final section = await repo.section(DemoSeed.cabbageFieldId);
      await repo.updateSection(
        mutationId: '5e5e5e5e-0000-4000-8000-000000000001',
        sectionId: section.id,
        expectedRevision: section.revision,
        name: section.name,
        areaM2: section.areaM2.raw,
      );
      await pumpFarmApp(tester, location: _cabbage, storage: db);
      await revealOnPage(tester, find.text('Check the drip line'));

      Finder within(String text, Finder inner) => find.descendant(
        of: find
            .ancestor(of: find.text(text), matching: find.byType(InkWell))
            .first,
        matching: inner,
      );
      expect(within('Check the drip line', chip('queued')), findsOneWidget);

      await setDelivery(db, task.id, 'failed');
      await tester.pumpAndSettle();
      await revealOnPage(tester, find.byKey(ValueKey('retry-${task.id}')));
      expect(within('Check the drip line', chip('failed')), findsOneWidget);
      await tester.tap(find.byKey(ValueKey('retry-${task.id}')));
      await tester.pumpAndSettle();
      expect(find.byKey(ValueKey('retry-${task.id}')), findsNothing);
      final taskRow = (await db.select(db.syncMutations).get()).singleWhere(
        (r) => r.recordId == task.id,
      );
      expect(taskRow.deliveryState, 'pending');

      await setDelivery(db, section.id, 'failed');
      await tester.pumpAndSettle();
      final retrySection = find.byKey(ValueKey('retry-${section.id}'));
      await revealOnPage(tester, retrySection);
      expectNoFailureLanguage(tester);
      await tester.tap(retrySection);
      await tester.pumpAndSettle();
      expect(retrySection, findsNothing);
      final sectionRow = (await db.select(db.syncMutations).get()).singleWhere(
        (r) => r.recordId == section.id,
      );
      expect(sectionRow.deliveryState, 'pending');
      expect(sectionRow.budgetCount, 0);

      await setDelivery(db, section.id, 'synced');
      await setDelivery(db, task.id, 'synced');
      await tester.pumpAndSettle();
      expect(chip('sent'), findsNWidgets(2));
    },
  );
}
