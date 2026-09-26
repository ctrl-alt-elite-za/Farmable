/// Schema v6: when the feed was last read to its end, added to a phone that
/// already has a cursor — which must survive the upgrade untouched.
library;

import 'dart:io';

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('a v5 phone keeps its cursor and gains the pulled-at column', () async {
    final directory = await Directory.systemTemp.createTemp('almanac-v6-');
    addTearDown(() => directory.delete(recursive: true));
    final file = File('${directory.path}/farm.sqlite');
    final at = DateTime.utc(2026, 9, 26);

    var db = AlmanacDatabase(NativeDatabase(file));
    await DemoSeed(db, now: () => at).ensureSeeded();
    // Back to v5: the cursor table as it was before it had a timestamp.
    await db.customStatement('DROP TABLE sync_cursors');
    await db.customStatement(
      'CREATE TABLE sync_cursors (owner_id TEXT NOT NULL, '
      'farm_id TEXT NOT NULL, cursor INTEGER NOT NULL, '
      'PRIMARY KEY (owner_id, farm_id))',
    );
    await db.customStatement(
      "INSERT INTO sync_cursors VALUES ('${DemoSeed.ownerId}', "
      "'${DemoSeed.farmId}', 7)",
    );
    await db.customStatement('PRAGMA user_version = 5');
    await db.close();

    db = AlmanacDatabase(NativeDatabase(file));
    addTearDown(db.close);
    final row = await db.select(db.syncCursors).getSingle();
    expect(row.cursor, 7);
    expect(row.pulledAt, isNull);
    await db
        .update(db.syncCursors)
        .write(SyncCursorsCompanion(pulledAt: Value(at)));
    expect(
      (await db.select(db.syncCursors).getSingle()).pulledAt!.isAtSameMomentAs(
        at,
      ),
      isTrue,
    );
    expect(
      (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
        'user_version',
      ),
      6,
    );
  });
}
