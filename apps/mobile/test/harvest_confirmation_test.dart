/// "Cleared" on Home (#12): stands the planting down once, however many
/// times it is sent, and survives the app being restarted before it syncs.
library;

import 'package:almanac/data/local/database.dart';
import 'package:almanac/data/local/local_farm_repository.dart';
import 'package:almanac/data/local/seed.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';

final _today = DateTime(2026, 9, 20);

void main() {
  late AlmanacDatabase db;
  late LocalFarmRepository repo;

  setUp(() async {
    db = AlmanacDatabase.memory();
    repo = LocalFarmRepository(db, now: () => _today);
    await DemoSeed(db, now: () => _today).ensureSeeded();
  });

  tearDown(() => db.close());

  Future<int> queued() async => (await db.select(db.syncMutations).get())
      .where((m) => m.recordType == 'planting')
      .length;

  test('the same key twice is one change and one queued mutation', () async {
    final before = await queued();
    await repo.clearPlanting(DemoSeed.cabbageFieldId, mutationId: 'k-1');
    await repo.clearPlanting(DemoSeed.cabbageFieldId, mutationId: 'k-1');

    expect(await queued(), before + 1);
    final section = await repo.watchSection(DemoSeed.cabbageFieldId).first;
    expect(section!.isAvailable, isTrue);
    final mutation = (await db.select(db.syncMutations).get()).last;
    expect(mutation.mutationId, 'k-1');
    expect(mutation.payload, contains('"isCurrent":false'));
  });

  test('a cleared section stays cleared after a restart', () async {
    await repo.clearPlanting(DemoSeed.cabbageFieldId, mutationId: 'k-1');
    final reopened = LocalFarmRepository(db, now: () => _today);
    final section = await reopened.watchSection(DemoSeed.cabbageFieldId).first;
    expect(section!.isAvailable, isTrue);
    // A retry after the restart, with the key it was first sent under.
    final before = await queued();
    await reopened.clearPlanting(DemoSeed.cabbageFieldId, mutationId: 'k-1');
    expect(await queued(), before);
  });

  test('a section with nothing planted is left alone', () async {
    await repo.clearPlanting(DemoSeed.cabbageFieldId, mutationId: 'k-1');
    final before = await queued();
    await repo.clearPlanting(DemoSeed.cabbageFieldId, mutationId: 'k-2');
    expect(await queued(), before);
  });

  test('the last complete pull is what Home measures age from', () async {
    expect(await repo.watchLastPulled().first, isNull);
    final at = DateTime.utc(2026, 9, 20, 6);
    await db
        .into(db.syncCursors)
        .insert(
          SyncCursorsCompanion.insert(
            ownerId: DemoSeed.ownerId,
            farmId: DemoSeed.farmId,
            cursor: 3,
            pulledAt: Value(at),
          ),
        );
    expect((await repo.watchLastPulled().first)!.isAtSameMomentAs(at), isTrue);
  });
}
