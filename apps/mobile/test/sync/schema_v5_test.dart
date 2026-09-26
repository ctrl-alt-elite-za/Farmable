/// Schema v5: the change-feed cursor, added to a phone that already has
/// queued work — which must survive the upgrade untouched and still send.
library;

import 'dart:io';

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a v4 phone keeps its queue and gains the cursor table', () async {
    final directory = await Directory.systemTemp.createTemp('almanac-v5-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/farm.sqlite');
    final at = DateTime.utc(2026, 9, 25);

    var db = AlmanacDatabase(NativeDatabase(file));
    await DemoSeed(db, now: () => at).ensureSeeded();
    await db
        .into(db.syncMutations)
        .insert(
          SyncMutationsCompanion.insert(
            mutationId: '9a9a9a9a-0000-4000-8000-000000000005',
            farmId: DemoSeed.farmId,
            ownerId: DemoSeed.ownerId,
            operation: 'create',
            recordType: 'section',
            recordId: DemoSeed.cabbageFieldId,
            createdAt: at,
            payload: const Value('{"id":"x"}'),
          ),
        );
    // Back to v4: the database as it was before the cursor existed.
    await db.customStatement('DROP TABLE sync_cursors');
    await db.customStatement('PRAGMA user_version = 4');
    await db.close();

    db = AlmanacDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final queued = await db.select(db.syncMutations).getSingle();
    expect(queued.recordType, 'section');
    expect(queued.payload, '{"id":"x"}');
    expect(queued.deliveryState, 'pending');
    await db
        .into(db.syncCursors)
        .insert(
          SyncCursorsCompanion.insert(
            ownerId: DemoSeed.ownerId,
            farmId: DemoSeed.farmId,
            cursor: 7,
          ),
        );
    expect((await db.select(db.syncCursors).getSingle()).cursor, 7);
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      db.schemaVersion,
    );
  });
}
