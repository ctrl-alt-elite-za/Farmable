import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import '../../domain/farm_records.dart' as rec;
import '../../domain/farm_records_repository.dart';
import '../../domain/farm_repository.dart';
import '../../domain/models.dart' as demo;
import '../../domain/money.dart';
import '../../domain/planning/acceptance.dart';
import '../../domain/planning/planner.dart';
import 'database.dart';

/// The farm, read from and written to the phone.
///
/// This is the source of truth for everything Home and Zone Detail show. It
/// never touches the network — not as a fallback, not on a timer, not at all.
/// Sync is a separate concern that will drain [SyncMutations] and reconcile
/// versions; until it exists, records sit at `pending` and the UI says so
/// calmly.
///
/// It implements two interfaces:
///
/// * [FarmRecordsRepository] — what the screens use. Modelled on the real
///   backend tables.
/// * [FarmRepository] — the `demo_api` contract, so the app can still be
///   pointed at the prototype API without a screen knowing which it got.
///   [preview] is served from the ported planner on this phone; the plan
///   *persistence* methods on that contract still belong to the server, and
///   the local equivalent is [acceptPlan].
class LocalFarmRepository implements FarmRecordsRepository, FarmRepository {
  final AlmanacDatabase db;

  /// Injectable so a test can pin "today" and assert on overdue, "in 7 days"
  /// and "92 days" without the assertions rotting overnight.
  final DateTime Function() now;

  LocalFarmRepository(this.db, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  // ---------------------------------------------------------------- reads

  @override
  Stream<rec.FarmSnapshot?> watchFarm() => _watch([
    db.users,
    db.farms,
    db.sections,
    db.plantings,
    db.observations,
    db.farmTasks,
    db.financialRecords,
    db.sectionProjections,
    db.sectionDetails,
  ], _loadFarm);

  @override
  Stream<rec.SectionSummary?> watchSection(String sectionId) => _watch([
    db.sections,
    db.plantings,
    db.observations,
    db.farmTasks,
    db.financialRecords,
    db.sectionProjections,
    db.sectionDetails,
  ], () => _loadSection(sectionId));

  @override
  Stream<List<rec.Observation>> watchObservations(String sectionId) =>
      _watch([db.observations], () => _observations(sectionId));

  @override
  Stream<List<rec.FarmTask>> watchTimeline(String sectionId) =>
      _watch([db.farmTasks], () => _timeline(sectionId));

  @override
  Stream<int> watchPendingChanges() => _watch([
    db.observations,
    db.farmTasks,
    db.financialRecords,
    db.sections,
    db.plantings,
  ], _pendingChanges);

  Future<rec.FarmSnapshot?> _loadFarm() async {
    final farmRow = await _farmRow();
    if (farmRow == null) return null;
    final user = await (db.select(db.users)..limit(1)).getSingleOrNull();
    final sections = await _sectionRows();

    final summaries = <rec.SectionSummary>[];
    for (final s in sections) {
      summaries.add(await _summarise(s));
    }

    return rec.FarmSnapshot(
      farm: _toFarm(farmRow),
      // First name only. "Hello, Sipho" — the guide is explicit that this is
      // not "Welcome back, User".
      farmerFirstName: (user?.displayName ?? '').split(' ').first,
      sections: summaries,
      upcoming: await _upcoming(),
      pendingChanges: await _pendingChanges(),
    );
  }

  Future<rec.SectionSummary?> _loadSection(String sectionId) async {
    final row =
        await (db.select(db.sections)
              ..where((t) => t.id.equals(sectionId) & t.deletedAt.isNull()))
            .getSingleOrNull();
    if (row == null) return null;
    return _summarise(row);
  }

  Future<rec.SectionSummary> _summarise(Section row) async {
    final planting =
        await (db.select(db.plantings)..where(
              (t) =>
                  t.sectionId.equals(row.id) &
                  t.isCurrent.equals(true) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();

    final projection = await (db.select(
      db.sectionProjections,
    )..where((t) => t.sectionId.equals(row.id))).getSingleOrNull();

    final detail = await (db.select(
      db.sectionDetails,
    )..where((t) => t.sectionId.equals(row.id))).getSingleOrNull();

    final latest =
        await (db.select(db.observations)
              ..where((t) => t.sectionId.equals(row.id) & t.deletedAt.isNull())
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ])
              ..limit(1))
            .getSingleOrNull();

    final next =
        await (db.select(db.farmTasks)
              ..where(
                (t) =>
                    t.sectionId.equals(row.id) &
                    t.deletedAt.isNull() &
                    t.status.isIn(const ['pending', 'in_progress']),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.dueDate)])
              ..limit(1))
            .getSingleOrNull();

    final spent = await _spent(row.id);

    return rec.SectionSummary(
      section: _toSection(row, detail),
      planting: planting == null ? null : _toPlanting(planting),
      projection: projection == null ? null : _toProjection(projection),
      latestObservation: latest == null ? null : _toObservation(latest),
      nextTask: next == null ? null : _toTask(next),
      spentSoFar: spent,
      pendingChanges: await _sectionPending(row.id),
    );
  }

  /// "R6,200 spent so far" — the sum of expenses booked against the section,
  /// not a number anyone typed.
  Future<Cents> _spent(String sectionId) async {
    final sum = db.financialRecords.amountCents.sum();
    final query = db.selectOnly(db.financialRecords)
      ..addColumns([sum])
      ..where(
        db.financialRecords.sectionId.equals(sectionId) &
            db.financialRecords.deletedAt.isNull() &
            db.financialRecords.type.equals('expense'),
      );
    final row = await query.getSingleOrNull();
    return Cents(row?.read(sum) ?? 0);
  }

  Future<List<rec.Observation>> _observations(String sectionId) async {
    final rows =
        await (db.select(db.observations)
              ..where(
                (t) => t.sectionId.equals(sectionId) & t.deletedAt.isNull(),
              )
              ..orderBy([
                (t) => OrderingTerm(
                  expression: t.createdAt,
                  mode: OrderingMode.desc,
                ),
              ]))
            .get();
    return rows.map(_toObservation).toList();
  }

  /// Ordered strictly by due date.
  ///
  /// The design mock lists a 10 September item above an 8 August one; that
  /// reads as an oversight in the mock rather than an intention, and #11 asks
  /// for the timeline to be sorted correctly. A season read top to bottom is
  /// the point of the component.
  Future<List<rec.FarmTask>> _timeline(String sectionId) async {
    final rows =
        await (db.select(db.farmTasks)
              ..where(
                (t) => t.sectionId.equals(sectionId) & t.deletedAt.isNull(),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.dueDate)]))
            .get();
    return rows.map(_toTask).toList();
  }

  Future<List<rec.FarmTask>> _upcoming() async {
    final rows =
        await (db.select(db.farmTasks)
              ..where(
                (t) =>
                    t.deletedAt.isNull() &
                    t.status.isIn(const ['pending', 'in_progress']),
              )
              ..orderBy([(t) => OrderingTerm(expression: t.dueDate)])
              ..limit(4))
            .get();
    return rows.map(_toTask).toList();
  }

  /// Records the farmer has created or changed that the server has not seen.
  ///
  /// Counted from each record's own `sync_state`, not from the outbox: the
  /// outbox exists so a replayed mutation cannot create a second server
  /// record, and a record edited three times offline is one thing waiting,
  /// not three.
  Future<int> _pendingChanges() async {
    var total = 0;
    total += await _countPending(db.observations);
    total += await _countPending(db.farmTasks);
    total += await _countPending(db.financialRecords);
    total += await _countPending(db.sections);
    total += await _countPending(db.plantings);
    return total;
  }

  Future<int> _sectionPending(String sectionId) async {
    var total = 0;
    total += await _countPending(db.observations, sectionId: sectionId);
    total += await _countPending(db.farmTasks, sectionId: sectionId);
    total += await _countPending(db.financialRecords, sectionId: sectionId);
    return total;
  }

  Future<int> _countPending(
    TableInfo<Table, dynamic> table, {
    String? sectionId,
  }) async {
    final columns = table.columnsByName;
    var predicate =
        columns['sync_state']!.equals('pending') &
        columns['deleted_at']!.isNull();
    if (sectionId != null) {
      final column = columns['section_id'];
      if (column == null) return 0;
      predicate = predicate & column.equals(sectionId);
    }
    final count = countAll();
    final query = db.selectOnly(table)
      ..addColumns([count])
      ..where(predicate);
    final row = await query.getSingleOrNull();
    return row?.read(count) ?? 0;
  }

  // --------------------------------------------------------------- writes

  @override
  Future<rec.Observation> createObservation({
    required String sectionId,
    required String type,
    required String note,
    required rec.HealthState healthStatus,
    String? actionTaken,
    int? healthScore,
    bool createdByVoice = false,
  }) async {
    final section = await _requireSection(sectionId);
    final at = now();
    final row = ObservationsCompanion.insert(
      id: newUuid(),
      farmId: section.farmId,
      ownerId: section.ownerId,
      sectionId: sectionId,
      type: type,
      note: note,
      healthStatus: Value(healthStatus.wire),
      actionTaken: Value(actionTaken),
      createdByVoice: Value(createdByVoice),
      healthScore: Value(healthScore),
      createdAt: at,
      updatedAt: at,
    );

    await db.transaction(() async {
      await db.into(db.observations).insert(row);
      await _enqueue(
        farmId: section.farmId,
        ownerId: section.ownerId,
        operation: 'create',
        recordType: 'observation',
        recordId: row.id.value,
        at: at,
      );
    });

    return (await _observationById(row.id.value))!;
  }

  @override
  Future<rec.Observation> updateObservation({
    required String observationId,
    required String type,
    required String note,
    required rec.HealthState healthStatus,
    String? actionTaken,
  }) async {
    final existing = await (db.select(
      db.observations,
    )..where((t) => t.id.equals(observationId))).getSingle();
    final at = now();

    await db.transaction(() async {
      await (db.update(
        db.observations,
      )..where((t) => t.id.equals(observationId))).write(
        ObservationsCompanion(
          type: Value(type),
          note: Value(note),
          healthStatus: Value(healthStatus.wire),
          actionTaken: Value(actionTaken),
          // An edited record has to reach the server again, so it goes back
          // to pending and its version moves — the same optimistic-concurrency
          // contract the server enforces.
          version: Value(existing.version + 1),
          syncState: const Value('pending'),
          updatedAt: Value(at),
        ),
      );
      await _enqueue(
        farmId: existing.farmId,
        ownerId: existing.ownerId,
        operation: 'update',
        recordType: 'observation',
        recordId: observationId,
        at: at,
      );
    });

    return (await _observationById(observationId))!;
  }

  @override
  Future<void> deleteObservation(String observationId) async {
    final existing = await (db.select(
      db.observations,
    )..where((t) => t.id.equals(observationId))).getSingle();
    final at = now();

    await db.transaction(() async {
      // A tombstone, not a row removal: a delete performed in airplane mode
      // has to be able to sync, and a deleted row has nothing to sync from.
      await (db.update(
        db.observations,
      )..where((t) => t.id.equals(observationId))).write(
        ObservationsCompanion(
          deletedAt: Value(at),
          version: Value(existing.version + 1),
          syncState: const Value('pending'),
          updatedAt: Value(at),
        ),
      );
      await _enqueue(
        farmId: existing.farmId,
        ownerId: existing.ownerId,
        operation: 'delete',
        recordType: 'observation',
        recordId: observationId,
        at: at,
      );
    });
  }

  @override
  Future<rec.FarmTask> createTask({
    required String sectionId,
    required String title,
    String? description,
    required DateTime dueDate,
    int? expectedCostCents,
  }) async {
    final section = await _requireSection(sectionId);
    final at = now();
    final row = FarmTasksCompanion.insert(
      id: newUuid(),
      farmId: section.farmId,
      ownerId: section.ownerId,
      sectionId: sectionId,
      title: title,
      description: Value(description),
      dueDate: _day(dueDate),
      expectedCostCents: Value(expectedCostCents),
      createdAt: at,
      updatedAt: at,
    );

    await db.transaction(() async {
      await db.into(db.farmTasks).insert(row);
      await _enqueue(
        farmId: section.farmId,
        ownerId: section.ownerId,
        operation: 'create',
        recordType: 'farm_task',
        recordId: row.id.value,
        at: at,
      );
    });

    return (await _taskById(row.id.value))!;
  }

  @override
  Future<rec.FarmTask> updateTask({
    required String taskId,
    required String title,
    String? description,
    required DateTime dueDate,
    int? expectedCostCents,
  }) => _writeTask(
    taskId,
    'update',
    (version, at) => FarmTasksCompanion(
      title: Value(title),
      description: Value(description),
      dueDate: Value(_day(dueDate)),
      expectedCostCents: Value(expectedCostCents),
      version: Value(version),
      syncState: const Value('pending'),
      updatedAt: Value(at),
    ),
  );

  @override
  Future<rec.FarmTask> rescheduleTask(String taskId, DateTime dueDate) =>
      _writeTask(
        taskId,
        'reschedule',
        (version, at) => FarmTasksCompanion(
          dueDate: Value(_day(dueDate)),
          version: Value(version),
          syncState: const Value('pending'),
          updatedAt: Value(at),
        ),
      );

  @override
  Future<rec.FarmTask> setTaskStatus(String taskId, rec.TaskStatus status) =>
      _writeTask(
        taskId,
        'update',
        (version, at) => FarmTasksCompanion(
          status: Value(status.wire),
          version: Value(version),
          syncState: const Value('pending'),
          updatedAt: Value(at),
        ),
      );

  @override
  Future<void> deleteTask(String taskId) => _writeTask(
    taskId,
    'delete',
    (version, at) => FarmTasksCompanion(
      deletedAt: Value(at),
      version: Value(version),
      syncState: const Value('pending'),
      updatedAt: Value(at),
    ),
  );

  Future<rec.FarmTask> _writeTask(
    String taskId,
    String operation,
    FarmTasksCompanion Function(int version, DateTime at) build,
  ) async {
    final existing = await (db.select(
      db.farmTasks,
    )..where((t) => t.id.equals(taskId))).getSingle();
    final at = now();

    await db.transaction(() async {
      await (db.update(db.farmTasks)..where((t) => t.id.equals(taskId))).write(
        build(existing.version + 1, at),
      );
      await _enqueue(
        farmId: existing.farmId,
        ownerId: existing.ownerId,
        operation: operation,
        recordType: 'farm_task',
        recordId: taskId,
        at: at,
      );
    });

    return (await _taskById(taskId))!;
  }

  /// One outbox row per farmer action.
  ///
  /// The id is minted here and never regenerated, so a retry after a failed
  /// send — or after the app restarts — carries the same `mutation_id` the
  /// server deduplicates on. That is what makes syncing the same local
  /// mutation twice create one server record.
  Future<void> _enqueue({
    required String farmId,
    required String ownerId,
    required String operation,
    required String recordType,
    required String recordId,
    required DateTime at,
  }) => db
      .into(db.syncMutations)
      .insert(
        SyncMutationsCompanion.insert(
          mutationId: newUuid(),
          farmId: farmId,
          ownerId: ownerId,
          operation: operation,
          recordType: recordType,
          recordId: recordId,
          createdAt: at,
        ),
      );

  // ------------------------------------------------------------- plumbing

  /// The section a write is about to attach to.
  ///
  /// Deleted rows are tombstoned rather than removed, and every read path
  /// already filters them out, so a write that did not would be the one way to
  /// add a record to a section the farmer has deleted. Throwing is the same
  /// answer this gives for an id that never existed, and the screen above it
  /// already navigates back when a section goes.
  Future<Section> _requireSection(String sectionId) => (db.select(
    db.sections,
  )..where((t) => t.id.equals(sectionId) & t.deletedAt.isNull())).getSingle();

  Future<rec.Observation?> _observationById(String id) async {
    final row = await (db.select(
      db.observations,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toObservation(row);
  }

  Future<rec.FarmTask?> _taskById(String id) async {
    final row = await (db.select(
      db.farmTasks,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toTask(row);
  }

  Future<Farm?> _farmRow() =>
      (db.select(db.farms)
            ..where((t) => t.deletedAt.isNull())
            ..limit(1))
          .getSingleOrNull();

  Future<List<Section>> _sectionRows() =>
      (db.select(db.sections)
            ..where((t) => t.deletedAt.isNull())
            ..orderBy([(t) => OrderingTerm(expression: t.createdAt)]))
          .get();

  /// Re-runs [load] on first listen and again whenever any of [tables]
  /// changes.
  ///
  /// Subscribing to the change feed *before* the first load is deliberate: a
  /// write that lands while the first snapshot is being assembled would
  /// otherwise be silently dropped, and the screen would show a farm that is
  /// one observation out of date with no way to notice. Overlapping loads are
  /// coalesced so a burst of writes costs one recomputation, not five.
  Stream<T> _watch<T>(
    List<TableInfo<Table, dynamic>> tables,
    Future<T> Function() load,
  ) {
    late StreamSubscription<void> subscription;
    late StreamController<T> controller;
    var running = false;
    var repeat = false;

    Future<void> emit() async {
      if (running) {
        repeat = true;
        return;
      }
      running = true;
      try {
        do {
          repeat = false;
          final value = await load();
          if (!controller.isClosed) controller.add(value);
        } while (repeat);
      } catch (error, stackTrace) {
        // Nothing awaits emit() — it is driven by the change feed and by
        // onListen — so an escaping exception would be an unhandled async
        // error and the stream would simply go quiet. A silent stream leaves
        // Home on its loading branch forever, which is a blank screen with no
        // spinner and no way back. Forwarding it means the screen can say
        // storage would not open and offer the retry it already has.
        if (!controller.isClosed) controller.addError(error, stackTrace);
      } finally {
        running = false;
      }
    }

    controller = StreamController<T>(
      onListen: () {
        subscription = db
            .tableUpdates(TableUpdateQuery.onAllTables(tables))
            .listen((_) => emit());
        emit();
      },
      onCancel: () => subscription.cancel(),
    );
    return controller.stream;
  }

  /// Dates on the server are `Date`, not timestamps. Truncating here keeps
  /// "is this overdue?" from depending on the time of day a task was typed.
  static DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  rec.Farm _toFarm(Farm r) => rec.Farm(
    id: r.id,
    ownerId: r.ownerId,
    name: r.name,
    locality: r.locality,
    version: r.version,
    syncState: rec.SyncState.parse(r.syncState),
  );

  rec.FarmSection _toSection(Section r, SectionDetail? d) => rec.FarmSection(
    id: r.id,
    farmId: r.farmId,
    name: r.name,
    areaM2: r.areaM2 == null ? null : DecimalString(r.areaM2!),
    version: r.version,
    syncState: rec.SyncState.parse(r.syncState),
    description: d?.description,
    waterNote: d?.waterNote,
    soilNote: d?.soilNote,
    marketNote: d?.marketNote,
  );

  rec.Planting _toPlanting(Planting r) => rec.Planting(
    id: r.id,
    sectionId: r.sectionId,
    crop: r.crop,
    variety: r.variety,
    plantedOn: r.plantedOn,
    isCurrent: r.isCurrent,
  );

  rec.Observation _toObservation(Observation r) => rec.Observation(
    id: r.id,
    sectionId: r.sectionId,
    type: r.type,
    note: r.note,
    healthStatus: rec.HealthState.parse(r.healthStatus),
    actionTaken: r.actionTaken,
    createdByVoice: r.createdByVoice,
    createdAt: r.createdAt,
    syncState: rec.SyncState.parse(r.syncState),
    healthScore: r.healthScore,
    localMediaId: r.localMediaId,
  );

  rec.FarmTask _toTask(FarmTask r) => rec.FarmTask(
    id: r.id,
    sectionId: r.sectionId,
    title: r.title,
    description: r.description,
    dueDate: r.dueDate,
    status: rec.TaskStatus.parse(r.status),
    expectedCost: r.expectedCostCents == null
        ? null
        : Cents(r.expectedCostCents!),
    syncState: rec.SyncState.parse(r.syncState),
  );

  rec.SectionProjection _toProjection(SectionProjection r) =>
      rec.SectionProjection(
        sectionId: r.sectionId,
        expectedProfit: Cents(r.expectedProfitCents),
        expectedCost: Cents(r.expectedCostCents),
        harvestStart: r.harvestStart,
        harvestEnd: r.harvestEnd,
        planId: r.planId,
      );

  // ------------------------------------------------- demo_api contract
  //
  // `FarmRepository` is the prototype API's shape. Serving it from local
  // storage keeps a single contract in front of the app, but two of its
  // concepts do not survive the trip and neither is papered over:
  //
  //  * `Crop` is an enum of cabbage and spinach. The demo farm has tomatoes,
  //    which the enum cannot express, so [Section.currentCrop] comes back null
  //    for them. Home and Zone Detail read `SectionSummary.cropLabel` — free
  //    text, like the server's column — and never touch this.
  //  * The planner is a server-side engine. It is not reimplemented here; the
  //    planning methods report the connection is unavailable instead of
  //    returning numbers nobody computed.

  @override
  String? get sessionToken => null;

  @override
  Future<demo.Dashboard> startSession() => farm();

  @override
  Future<demo.Dashboard> restoreSession(String token) => farm();

  @override
  Future<demo.Dashboard> farm() async {
    final farmRow = await _farmRow();
    if (farmRow == null) throw const SessionExpired('No farm on this phone');
    final rows = await _sectionRows();
    final sections = <demo.Section>[];
    var totalArea = 0.0;
    for (final row in rows) {
      sections.add(await _toDemoSection(row));
      totalArea += double.tryParse(row.areaM2 ?? '') ?? 0;
    }
    return demo.Dashboard(
      farmId: farmRow.id,
      name: farmRow.name,
      sections: sections,
      totalSectionAreaM2: DecimalString(totalArea.toStringAsFixed(2)),
      approvedPlanIds: await _approvedPlanIds(),
      // The provenance disclaimer the design is required to show. These are
      // sample figures, not a forecast.
      label: 'Example farm data stored on this phone',
    );
  }

  @override
  Future<demo.Section> section(String sectionId) async =>
      _toDemoSection(await _requireSection(sectionId));

  @override
  Future<demo.Section> createSection({
    required String mutationId,
    required String name,
    required String areaM2,
  }) async {
    final farmRow = await _farmRow();
    if (farmRow == null) throw const SessionExpired('No farm on this phone');
    final at = now();
    final id = newUuid();
    await db.transaction(() async {
      await db
          .into(db.sections)
          .insert(
            SectionsCompanion.insert(
              id: id,
              farmId: farmRow.id,
              ownerId: farmRow.ownerId,
              name: name,
              areaM2: Value(areaM2),
              areaSource: const Value('farmer_supplied'),
              createdAt: at,
              updatedAt: at,
            ),
          );
      await _enqueueWithId(
        mutationId: mutationId,
        farmId: farmRow.id,
        ownerId: farmRow.ownerId,
        operation: 'create',
        recordType: 'section',
        recordId: id,
        at: at,
      );
    });
    return _toDemoSection(await _requireSection(id));
  }

  @override
  Future<demo.Section> updateSection({
    required String mutationId,
    required String sectionId,
    required int expectedRevision,
    required String name,
    required String areaM2,
  }) async {
    final existing = await _requireSection(sectionId);
    // The server refuses a blind write and so does this, for the same reason:
    // silently clobbering an edit made on another device is worse than making
    // the caller reload.
    if (existing.version != expectedRevision) throw const RevisionConflict();

    final at = now();
    await db.transaction(() async {
      await (db.update(
        db.sections,
      )..where((t) => t.id.equals(sectionId))).write(
        SectionsCompanion(
          name: Value(name),
          areaM2: Value(areaM2),
          version: Value(existing.version + 1),
          syncState: const Value('pending'),
          updatedAt: Value(at),
        ),
      );
      await _enqueueWithId(
        mutationId: mutationId,
        farmId: existing.farmId,
        ownerId: existing.ownerId,
        operation: 'update',
        recordType: 'section',
        recordId: sectionId,
        at: at,
      );
    });
    return _toDemoSection(await _requireSection(sectionId));
  }

  @override
  Future<void> deleteSection(
    String sectionId, {
    required String mutationId,
  }) async {
    final existing = await _requireSection(sectionId);
    final at = now();
    await db.transaction(() async {
      await (db.update(
        db.sections,
      )..where((t) => t.id.equals(sectionId))).write(
        SectionsCompanion(
          deletedAt: Value(at),
          version: Value(existing.version + 1),
          syncState: const Value('pending'),
          updatedAt: Value(at),
        ),
      );
      await _enqueueWithId(
        mutationId: mutationId,
        farmId: existing.farmId,
        ownerId: existing.ownerId,
        operation: 'delete',
        recordType: 'section',
        recordId: sectionId,
        at: at,
      );
    });
  }

  /// Runs the planner on this phone.
  ///
  /// Issue #22's runtime requirement: the farmer must be able to ask for a
  /// recommendation with no network round trip. `planSection` is a port of the
  /// backend's engine, checked against 26 responses captured from it in
  /// `test/planner_oracle_test.dart`, so the answer here is the answer the
  /// server would have given — it just does not need the server to give it.
  ///
  /// A result with `feasible == false` comes back as a *value*, not an
  /// exception. It carries the reason and, where money is the obstacle, the
  /// budget that would clear it.
  @override
  Future<demo.PlanningResult> preview(
    String sectionId,
    demo.PlanRequest request,
  ) async {
    final section = await _requireSection(sectionId);
    final area = section.areaM2;
    if (area == null) {
      throw const RequestRejected(
        'section_area_unknown',
        'This section has no measured area to plan over',
      );
    }
    return planSection(areaM2: DecimalString(area), request: request);
  }

  @override
  Future<void> acceptPlan(PlanAcceptance acceptance) async {
    final section = await _requireSection(acceptance.sectionId);
    final at = now();
    final planId = newUuid();

    await db.transaction(() async {
      await db
          .into(db.savedPlans)
          .insert(
            SavedPlansCompanion.insert(
              id: planId,
              farmId: section.farmId,
              ownerId: section.ownerId,
              sectionId: section.id,
              // Approved, because this write only happens after the farmer
              // confirmed. Nothing reaches storage in the `proposed` state —
              // an unconfirmed recommendation lives on the screen and nowhere
              // else, which is what makes cancelling it free.
              status: const Value('approved'),
              plan: jsonEncode(acceptance.record),
              approvedAt: Value(at),
              createdAt: at,
              updatedAt: at,
            ),
          );

      // One current planting per section, enforced by a partial unique index.
      // Standing the old one down before raising the new one is what keeps a
      // re-plan from violating it.
      await (db.update(db.plantings)..where(
            (t) =>
                t.sectionId.equals(section.id) &
                t.isCurrent.equals(true) &
                t.deletedAt.isNull(),
          ))
          .write(
            PlantingsCompanion(
              isCurrent: const Value(false),
              syncState: const Value('pending'),
              updatedAt: Value(at),
            ),
          );

      final plantingId = newUuid();
      await db
          .into(db.plantings)
          .insert(
            PlantingsCompanion.insert(
              id: plantingId,
              farmId: section.farmId,
              ownerId: section.ownerId,
              sectionId: section.id,
              crop: acceptance.crop.name,
              plantedOn: Value(_day(acceptance.plantingDate)),
              createdAt: at,
              updatedAt: at,
            ),
          );

      await db
          .into(db.sectionProjections)
          .insertOnConflictUpdate(
            SectionProjectionsCompanion.insert(
              sectionId: section.id,
              expectedProfitCents: acceptance.expectedProfit.value,
              expectedCostCents: acceptance.expectedCost.value,
              harvestStart: _day(acceptance.harvestStart),
              harvestEnd: _day(acceptance.harvestEnd),
              planId: Value(planId),
            ),
          );

      // The confirmation sheet says accepting "will replace that planting and
      // its schedule". Retiring the superseded steps in the same transaction
      // is what makes that sentence true — without it the timeline and the
      // Next-up queries return both schedules, and the farmer is looking at
      // two plans for one section with nothing to say which is live.
      //
      // Only pending work, and only steps a plan generated. A task the farmer
      // typed carries no plan id and is never touched by a replan; anything
      // done or cancelled is history and stays on the timeline.
      final superseded =
          await (db.select(db.farmTasks)..where(
                (t) =>
                    t.sectionId.equals(section.id) &
                    t.planId.isNotNull() &
                    t.deletedAt.isNull() &
                    t.status.isIn(const ['pending', 'in_progress']),
              ))
              .get();

      for (final task in superseded) {
        await (db.update(
          db.farmTasks,
        )..where((t) => t.id.equals(task.id))).write(
          FarmTasksCompanion(
            deletedAt: Value(at),
            version: Value(task.version + 1),
            syncState: const Value('pending'),
            updatedAt: Value(at),
          ),
        );
        await _enqueue(
          farmId: task.farmId,
          ownerId: task.ownerId,
          operation: 'delete',
          recordType: 'farm_task',
          recordId: task.id,
          at: at,
        );
      }

      for (final step in acceptance.timeline) {
        final taskId = newUuid();
        await db
            .into(db.farmTasks)
            .insert(
              FarmTasksCompanion.insert(
                id: taskId,
                farmId: section.farmId,
                ownerId: section.ownerId,
                sectionId: section.id,
                title: step.title,
                description: Value(step.note),
                dueDate: _day(step.due),
                expectedCostCents: Value(step.expectedCost?.value),
                // Whose schedule this is, so the next acceptance can retire it
                // without guessing from the title.
                planId: Value(planId),
                createdAt: at,
                updatedAt: at,
              ),
            );
        await _enqueue(
          farmId: section.farmId,
          ownerId: section.ownerId,
          operation: 'create',
          recordType: 'farm_task',
          recordId: taskId,
          at: at,
        );
      }

      await _enqueue(
        farmId: section.farmId,
        ownerId: section.ownerId,
        operation: 'create',
        recordType: 'planting',
        recordId: plantingId,
        at: at,
      );
      await _enqueue(
        farmId: section.farmId,
        ownerId: section.ownerId,
        operation: 'approve',
        recordType: 'saved_plan',
        recordId: planId,
        at: at,
      );
    });
  }

  @override
  Future<demo.SavedPlan> savePlan(
    String sectionId,
    demo.PlanRequest request, {
    required String mutationId,
  }) async => throw const Unreachable('Planning needs a connection');

  @override
  Future<demo.SavedPlan> replan(
    String planId,
    demo.PlanRequest request, {
    required String mutationId,
  }) async => throw const Unreachable('Planning needs a connection');

  @override
  Future<demo.SavedPlan> plan(String planId) async =>
      throw const Unreachable('Planning needs a connection');

  @override
  Future<demo.SavedPlan> approvePlan(
    String planId, {
    required String mutationId,
  }) async => throw const Unreachable('Planning needs a connection');

  Future<List<String>> _approvedPlanIds() async {
    final rows = await (db.select(
      db.savedPlans,
    )..where((t) => t.status.equals('approved') & t.deletedAt.isNull())).get();
    return rows.map((r) => r.id).toList();
  }

  Future<demo.Section> _toDemoSection(Section row) async {
    final planting =
        await (db.select(db.plantings)..where(
              (t) =>
                  t.sectionId.equals(row.id) &
                  t.isCurrent.equals(true) &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();
    final approved =
        await (db.select(db.savedPlans)..where(
              (t) =>
                  t.sectionId.equals(row.id) &
                  t.status.equals('approved') &
                  t.deletedAt.isNull(),
            ))
            .getSingleOrNull();

    return demo.Section(
      id: row.id,
      name: row.name,
      areaM2: DecimalString(row.areaM2 ?? '0'),
      areaSource: demo.AreaSource.parse(row.areaSource ?? 'farmer_supplied'),
      boundaryRing: null,
      revision: row.version,
      currentCrop: _asDemoCrop(planting?.crop),
      plannedPlanId: approved?.id,
    );
  }

  /// Null for a crop the demo enum cannot express — tomatoes, in this farm.
  /// Callers that need the real crop read the planting.
  static demo.Crop? _asDemoCrop(String? crop) {
    if (crop == null) return null;
    for (final c in demo.Crop.values) {
      if (c.name == crop) return c;
    }
    return null;
  }

  /// The demo contract hands us the mutation id, because the caller is
  /// expected to reuse it across retries. The records interface mints its own.
  Future<void> _enqueueWithId({
    required String mutationId,
    required String farmId,
    required String ownerId,
    required String operation,
    required String recordType,
    required String recordId,
    required DateTime at,
  }) => db
      .into(db.syncMutations)
      .insertOnConflictUpdate(
        SyncMutationsCompanion.insert(
          mutationId: mutationId,
          farmId: farmId,
          ownerId: ownerId,
          operation: operation,
          recordType: recordType,
          recordId: recordId,
          createdAt: at,
        ),
      );
}
