/// Schema v4: upload bookkeeping on `local_photos`, added to a phone that
/// already has queued photos — which must survive the upgrade untouched.
library;

import 'dart:io';

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'a v3 phone keeps its queued photo and gains the upload columns',
    () async {
      final directory = await Directory.systemTemp.createTemp('almanac-v4-');
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/farm.sqlite');
      final at = DateTime.utc(2026, 9, 23);

      var db = AlmanacDatabase(NativeDatabase(file));
      await DemoSeed(db, now: () => at).ensureSeeded();
      await db
          .into(db.localPhotos)
          .insert(
            LocalPhotosCompanion.insert(
              id: '9a9a9a9a-0000-4000-8000-000000000001',
              ownerId: DemoSeed.ownerId,
              farmId: DemoSeed.farmId,
              relativePath: 'x.jpg',
              contentType: 'image/jpeg',
              byteLength: 10,
            ),
          );
      // Back to v3: the table as it was before these columns existed.
      for (final column in [
        'upload_id',
        'failed_attempt_id',
        'recover_attempt_id',
        'purged_at',
      ]) {
        await db.customStatement(
          'ALTER TABLE local_photos DROP COLUMN $column',
        );
      }
      // Nor had the v5 change-feed cursor arrived.
      await db.customStatement('DROP TABLE sync_cursors');
      await db.customStatement('PRAGMA user_version = 3');
      await db.close();

      db = AlmanacDatabase(NativeDatabase(file));
      addTearDown(db.close);
      final photo = await db.select(db.localPhotos).getSingle();
      expect(photo.relativePath, 'x.jpg');
      expect(photo.uploadId, isNull);
      expect(photo.purgedAt, isNull);
      await (db.update(db.localPhotos)..where((t) => t.id.equals(photo.id)))
          .write(const LocalPhotosCompanion(uploadId: Value('u')));
      expect((await db.select(db.localPhotos).getSingle()).uploadId, 'u');
      expect(
        (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
          'user_version',
        ),
        db.schemaVersion,
      );
    },
  );
}
