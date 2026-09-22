import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'tables.dart';

export 'tables.dart';

part 'database.g.dart';

/// The app's local database — and, for everything the farm screens show, the
/// source of truth.
///
/// The server is sync on top of this, not the other way round. A screen reads
/// here and renders; a write lands here and returns. Nothing in the app waits
/// on the network before showing the farmer their farm, because the farmer is
/// on prepaid data with patchy coverage and being offline is a Tuesday.
@DriftDatabase(
  tables: [
    Users,
    Farms,
    Sections,
    Plantings,
    Observations,
    FarmTasks,
    FinancialRecords,
    SavedPlans,
    SectionProjections,
    SectionDetails,
    SyncMutations,
    SeedState,
    LocalPhotos,
  ],
)
class AlmanacDatabase extends _$AlmanacDatabase {
  AlmanacDatabase(super.e);

  /// On-device storage. `drift_flutter` puts the file in the app's documents
  /// directory and runs it on a background isolate, so a query cannot jank a
  /// scroll.
  AlmanacDatabase.onDevice() : super(driftDatabase(name: 'almanac'));

  /// For tests. Nothing touches the filesystem, so each test gets a farm of
  /// its own and they can run in parallel.
  AlmanacDatabase.memory() : super(NativeDatabase.memory());

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      if (from != 1 || to != 2) {
        throw StateError('unsupported_schema');
      }
      await transaction(() async {
        await m.addColumn(syncMutations, syncMutations.payload);
        await m.addColumn(syncMutations, syncMutations.recordVersion);
        await m.addColumn(syncMutations, syncMutations.dependencyId);
        await m.addColumn(syncMutations, syncMutations.deliveryState);
        await m.addColumn(syncMutations, syncMutations.attemptCount);
        await m.addColumn(syncMutations, syncMutations.budgetCount);
        await m.addColumn(syncMutations, syncMutations.nextAttemptAt);
        await m.addColumn(syncMutations, syncMutations.errorCode);
        await m.createTable(localPhotos);
        // Drift normally updates this after onUpgrade. Include it in our
        // transaction so a process kill cannot leave v2 columns tagged as v1.
        await customStatement('PRAGMA user_version = 2');
      });
    },
    onCreate: (m) async {
      await m.createAll();
      // The server enforces one current planting per section with a partial
      // unique index (`uq_plantings_current_section`). Carrying the same
      // constraint locally means a bug that would be rejected on sync is
      // rejected here first, where it is debuggable.
      await customStatement(
        'CREATE UNIQUE INDEX IF NOT EXISTS uq_plantings_current_section '
        'ON plantings (section_id) WHERE is_current = 1 AND deleted_at IS NULL',
      );
      // Every list the screens draw is "this section's live records, newest
      // or soonest first". Without these, each one is a table scan.
      await customStatement(
        'CREATE INDEX IF NOT EXISTS ix_observations_section_created '
        'ON observations (section_id, created_at)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS ix_farm_tasks_section_due '
        'ON farm_tasks (section_id, due_date)',
      );
      await customStatement(
        'CREATE INDEX IF NOT EXISTS ix_financial_records_section_date '
        'ON financial_records (section_id, date)',
      );
    },
    onUpgrade: (m, from, to) async {
      // v2 gives `farm_tasks` the plan that generated it, so accepting a plan
      // can retire the schedule it supersedes without touching the tasks a
      // farmer wrote. Every task that predates the column is null — which is
      // the honest answer: nothing recorded which plan they came from, and
      // treating them as plan steps would let a replan delete them.
      if (from < 2) await m.addColumn(farmTasks, farmTasks.planId);
    },
    beforeOpen: (details) async {
      if (details.versionBefore != null &&
          details.versionBefore! > schemaVersion) {
        throw StateError('unsupported_schema');
      }
      // Drift does not turn these on for us, and both matter here: without
      // foreign keys a section delete leaves orphaned observations, and the
      // default rollback journal makes a write block every open read.
      await customStatement('PRAGMA foreign_keys = ON');
      await customStatement('PRAGMA journal_mode = WAL');
    },
  );
}
