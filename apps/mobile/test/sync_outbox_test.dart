import 'dart:convert';
import 'dart:io';

import 'package:almanac/core/utils/ids.dart';
import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/offline_photos.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:almanac/data/local/sync_outbox.dart';
import 'package:almanac/domain/farm_records.dart' as rec;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Inspect a failed v1 migration without attempting to migrate it again.
class _VersionOneDatabase extends AlmanacDatabase {
  _VersionOneDatabase(super.e);
  @override
  int get schemaVersion => 1;
}

void main() {
  late AlmanacDatabase db;
  late LocalFarmRepository repo;
  late SyncOutbox outbox;
  late Directory directory;
  late OfflinePhotos photos;
  final at = DateTime.utc(2026, 9, 22);

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('farmable-outbox-');
    db = AlmanacDatabase(NativeDatabase(File('${directory.path}/farm.sqlite')));
    await DemoSeed(db, now: () => at).ensureSeeded();
    repo = LocalFarmRepository(db, now: () => at);
    outbox = SyncOutbox(db, ownerId: DemoSeed.ownerId, farmId: DemoSeed.farmId);
    photos = OfflinePhotos(
      Directory('${directory.path}/photos'),
      ownerId: DemoSeed.ownerId,
      farmId: DemoSeed.farmId,
    );
  });
  tearDown(() async {
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<rec.Observation> create() => repo.createObservation(
    sectionId: DemoSeed.cabbageFieldId,
    type: 'check',
    note: 'Original',
    healthStatus: rec.HealthState.onTrack,
  );

  test('snapshots edits in order and old acknowledgements cannot sync a newer version', () async {
    final observation = await create();
    final first = (await outbox.claim(at))!;
    await repo.updateObservation(
      observationId: observation.id,
      type: 'check',
      note: 'Edited',
      healthStatus: rec.HealthState.needsAttention,
    );
    final rows = await outbox.entries();
    expect(rows, hasLength(2));
    expect(jsonDecode(first.payload!)['note'], 'Original');
    expect(rows.last.dependencyId, first.mutationId);
    expect(await outbox.claim(at), isNull);
    await outbox.acknowledge(first, at);
    expect(
      (await repo.watchObservations(DemoSeed.cabbageFieldId).first)
          .firstWhere((r) => r.id == observation.id)
          .syncState,
      rec.SyncState.pending,
    );
    final second = (await outbox.claim(at))!;
    expect(jsonDecode(second.payload!)['note'], 'Edited');
    await outbox.acknowledge(second, at);
    expect(
      (await repo.watchObservations(DemoSeed.cabbageFieldId).first)
          .firstWhere((r) => r.id == observation.id)
          .syncState,
      rec.SyncState.synced,
    );
  });

  test(
    'concurrent edits receive distinct versions and ordered snapshots',
    () async {
      final observation = await create();
      await Future.wait([
        for (final note in ['First edit', 'Second edit'])
          repo.updateObservation(
            observationId: observation.id,
            type: 'check',
            note: note,
            healthStatus: rec.HealthState.onTrack,
          ),
      ]);
      final rows = await outbox.entries();
      expect(rows.map((r) => r.recordVersion), [1, 2, 3]);
      expect(rows[2].dependencyId, rows[1].mutationId);
      expect(rows.skip(1).map((r) => jsonDecode(r.payload!)['note']).toSet(), {
        'First edit',
        'Second edit',
      });
    },
  );

  test(
    'failed migration rolls back all newly added columns and preserves data',
    () async {
      await create();
      for (final column in [
        'payload',
        'record_version',
        'dependency_id',
        'delivery_state',
        'attempt_count',
        'budget_count',
        'next_attempt_at',
      ]) {
        await db.customStatement(
          'ALTER TABLE sync_mutations DROP COLUMN $column',
        );
      }
      // An unexpected column forces a failure late in the migration.
      await db.customStatement('DROP TABLE local_photos');
      // A v1 database predates plan_id too. Leaving it behind would make
      // the v3 step fail on a duplicate column and roll the whole
      // migration back.
      await db.customStatement('ALTER TABLE farm_tasks DROP COLUMN plan_id');
      await db.customStatement('PRAGMA user_version = 1');
      await db.close();
      db = AlmanacDatabase(
        NativeDatabase(File('${directory.path}/farm.sqlite')),
      );
      await expectLater(
        db.select(db.syncMutations).get(),
        throwsA(isA<Exception>()),
      );
      await db.close();
      db = _VersionOneDatabase(
        NativeDatabase(File('${directory.path}/farm.sqlite')),
      );
      final columns = await db
          .customSelect('PRAGMA table_info(sync_mutations)')
          .get();
      expect(
        columns.map((c) => c.read<String>('name')),
        isNot(contains('payload')),
      );
      expect(
        (await db
                .customSelect('SELECT count(*) AS n FROM sync_mutations')
                .getSingle())
            .read<int>('n'),
        1,
      );
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        1,
      );
    },
  );

  test('delete is a durable ordered tombstone', () async {
    final observation = await create();
    await repo.deleteObservation(observation.id);
    final rows = await outbox.entries();
    expect(rows.last.operation, 'delete');
    expect(rows.last.recordVersion, 2);
    expect(rows.last.dependencyId, rows.first.mutationId);
    expect(jsonDecode(rows.last.payload!)['deletedAt'], isNotNull);
  });

  test('record and snapshot roll back together on enqueue failure', () async {
    final before = await db.select(db.observations).get();
    await expectLater(
      repo.createObservation(
        sectionId: DemoSeed.cabbageFieldId,
        type: 'check',
        note: 'x' * 66000,
        healthStatus: rec.HealthState.onTrack,
      ),
      throwsStateError,
    );
    expect(await db.select(db.observations).get(), before);
    expect(await outbox.entries(), isEmpty);
  });

  test(
    'restart recovers interrupted claim with identity and attempts intact',
    () async {
      await create();
      final first = (await outbox.claim(at))!;
      await db.close();
      db = AlmanacDatabase(
        NativeDatabase(File('${directory.path}/farm.sqlite')),
      );
      outbox = SyncOutbox(
        db,
        ownerId: DemoSeed.ownerId,
        farmId: DemoSeed.farmId,
      );
      await outbox.recover();
      final next = (await outbox.claim(at))!;
      expect(next.mutationId, first.mutationId);
      expect(next.payload, first.payload);
      expect(next.attemptCount, 2);
      await expectLater(outbox.acknowledge(first, at), throwsStateError);
      expect((await outbox.entries()).single.syncedAt, isNull);
    },
  );

  test(
    'budget is bounded and manual retry preserves lifetime attempts and ID',
    () async {
      await create();
      for (var i = 1; i <= 8; i++) {
        final claim = (await outbox.claim(at))!;
        expect(claim.budgetCount, i);
        await outbox.release(
          claim,
          i == 8 ? 'failed' : 'pending',
          'transient',
          at,
        );
      }
      expect(await outbox.claim(at), isNull);
      final original = (await outbox.entries()).single;
      await outbox.retry(original.mutationId);
      final retry = (await outbox.claim(at))!;
      expect(retry.mutationId, original.mutationId);
      expect(retry.attemptCount, 9);
      expect(retry.budgetCount, 1);
    },
  );

  test(
    'other owners cannot claim, acknowledge, recover or retry work',
    () async {
      await create();
      final first = (await outbox.claim(at))!;
      final other = SyncOutbox(db, ownerId: newUuid(), farmId: DemoSeed.farmId);
      expect(await other.entries(), isEmpty);
      expect(await other.claim(at), isNull);
      await other.recover();
      await expectLater(other.acknowledge(first, at), throwsStateError);
      await expectLater(other.retry(first.mutationId), throwsStateError);
      expect((await outbox.entries()).single.deliveryState, 'syncing');
    },
  );

  test('legacy mutations survive v1 migration but are not sent with invented payloads', () async {
    final observation = await create();
    final id = (await outbox.entries()).single.mutationId;
    // Recreate exactly the v1 outbox shape from the already seeded v1 tables.
    for (final column in [
      'payload',
      'record_version',
      'dependency_id',
      'delivery_state',
      'attempt_count',
      'budget_count',
      'next_attempt_at',
      'error_code',
    ]) {
      await db.customStatement(
        'ALTER TABLE sync_mutations DROP COLUMN $column',
      );
    }
    await db.customStatement('DROP TABLE local_photos');
    // A v1 database predates plan_id too. Leaving it behind would make
    // the v3 step fail on a duplicate column and roll the whole
    // migration back.
    await db.customStatement('ALTER TABLE farm_tasks DROP COLUMN plan_id');
    await db.customStatement('PRAGMA user_version = 1');
    await db.close();
    db = AlmanacDatabase(NativeDatabase(File('${directory.path}/farm.sqlite')));
    outbox = SyncOutbox(db, ownerId: DemoSeed.ownerId, farmId: DemoSeed.farmId);
    final row = (await outbox.entries()).single;
    expect(row.mutationId, id);
    expect(row.payload, isNull);
    expect(row.syncedAt, isNull);
    expect(await outbox.claim(at), isNull);
    expect(
      await (db.select(
        db.observations,
      )..where((t) => t.id.equals(observation.id))).getSingle(),
      isNotNull,
    );
    expect(await db.select(db.localPhotos).get(), isEmpty);
  });

  test(
    'photo copy, observation, and two dependent mutations survive reopen',
    () async {
      final source = File('${directory.path}/capture.png');
      await source.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10, 1, 2]);
      final id = newUuid(), mutationId = newUuid();
      final capture = PhotoCapture(
        source: source.uri,
        mediaId: newUuid(),
        mutationId: newUuid(),
        contentType: 'image/png',
      );
      final service = OfflineObservations(outbox, photos, now: () => at);
      Future<Observation> save({String note = 'With photo'}) => service.save(
        id: id,
        mutationId: mutationId,
        sectionId: DemoSeed.cabbageFieldId,
        type: 'check',
        note: note,
        photo: capture,
      );
      await save();
      await source.delete(); // The camera cache is no longer needed.
      await save(); // Idempotent retry doesn't need the original capture.
      await expectLater(save(note: 'different'), throwsStateError);
      expect(await outbox.entries(), hasLength(2));
      final media = (await outbox.photo(capture.mediaId))!;
      expect(await File.fromUri(await photos.view(media)).exists(), isTrue);
      final upload = (await outbox.claim(at))!;
      expect(upload.recordType, 'media');
      expect(upload.payload, isNot(contains(directory.path)));
      await db.close();
      db = AlmanacDatabase(
        NativeDatabase(File('${directory.path}/farm.sqlite')),
      );
      outbox = SyncOutbox(
        db,
        ownerId: DemoSeed.ownerId,
        farmId: DemoSeed.farmId,
      );
      await outbox.recover();
      final retry = (await outbox.claim(at))!;
      final cloudId = newUuid();
      await outbox.acknowledge(retry, at, cloudId: cloudId);
      expect((await outbox.photo(capture.mediaId))!.cloudId, cloudId);
      expect((await outbox.claim(at))!.recordId, id);
      expect(await File.fromUri(await photos.view(media)).exists(), isTrue);
    },
  );

  test(
    'invalid signature and unsafe paths are rejected without deleting capture',
    () async {
      final source = File('${directory.path}/capture.png');
      await source.writeAsBytes([1, 2, 3]);
      await expectLater(
        photos.stage(source.uri, newUuid(), 'image/png'),
        throwsStateError,
      );
      expect(await source.exists(), isTrue);
      await expectLater(
        photos.stage(
          Uri.parse('https://example.com/photo'),
          newUuid(),
          'image/png',
        ),
        throwsArgumentError,
      );
      await expectLater(
        photos.stage(source.uri, '../escape', 'image/png'),
        throwsArgumentError,
      );
    },
  );

  test('failed observation transaction keeps the capture and never publishes a partial outbox', () async {
    final source = File('${directory.path}/capture.png');
    await source.writeAsBytes([137, 80, 78, 71, 13, 10, 26, 10]);
    final service = OfflineObservations(outbox, photos);
    await expectLater(
      service.save(
        id: newUuid(),
        mutationId: newUuid(),
        sectionId: newUuid(),
        type: 'check',
        note: 'Unknown section',
        photo: PhotoCapture(
          source: source.uri,
          mediaId: newUuid(),
          mutationId: newUuid(),
          contentType: 'image/png',
        ),
      ),
      throwsStateError,
    );
    expect(await outbox.entries(), isEmpty);
    expect(await db.select(db.localPhotos).get(), isEmpty);
    expect(await source.exists(), isTrue);
  });

  test('photo recovery only removes expired temporary files', () async {
    final folder = Directory(
      '${photos.root.path}/${photos.ownerId}/${photos.farmId}',
    );
    await folder.create(recursive: true);
    final old = File('${folder.path}/${newUuid()}.tmp');
    final fresh = File('${folder.path}/${newUuid()}.tmp');
    final retained = File('${folder.path}/${newUuid()}.png');
    for (final file in [old, fresh, retained]) {
      await file.writeAsBytes([1]);
    }
    await old.setLastModified(at.subtract(const Duration(days: 2)));
    await retained.setLastModified(at.subtract(const Duration(days: 2)));
    await fresh.setLastModified(at);
    await photos.recover(at);
    expect(await old.exists(), isFalse);
    expect(await fresh.exists(), isTrue);
    expect(await retained.exists(), isTrue);
  });

  test('failed dependencies and conflicts never drain automatically', () async {
    final observation = await create();
    await repo.deleteObservation(observation.id);
    final first = (await outbox.claim(at))!;
    await outbox.release(first, 'conflict', 'conflict', at);
    expect(await outbox.claim(at), isNull);
    expect(await outbox.nextDue(), isNull);
    await expectLater(outbox.retry(first.mutationId), throwsStateError);
  });
}
