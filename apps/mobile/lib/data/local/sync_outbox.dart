import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import 'database.dart';

/// Every record type the outbox can send, as the outbox names them.
const syncedRecordTypes = {
  'observation',
  'media',
  'section',
  'planting',
  'farm_task',
  'financial',
  'saved_plan',
};

/// Called inside the same transaction as the observation write. Preserve the
/// exact version being sent; reading the latest row during a retry is unsafe.
Future<void> enqueueObservation(
  AlmanacDatabase db,
  String id,
  String operation,
  DateTime at, {
  String? mutationId,
  String? photoDependency,
}) => enqueueRecord(
  db,
  'observation',
  id,
  operation,
  at,
  mutationId: mutationId,
  photoDependency: photoDependency,
);

/// Queues one farmer action on one record, with an immutable snapshot of the
/// record as that action left it.
///
/// Called inside the same transaction as the record write, so the snapshot
/// is exactly the version this mutation produced — reading the latest row at
/// send time would ship a later edit under an earlier mutation id, which the
/// server rightly refuses as `mutation_conflict`.
Future<void> enqueueRecord(
  AlmanacDatabase db,
  String recordType,
  String id,
  String operation,
  DateTime at, {
  String? mutationId,
  String? photoDependency,
}) async {
  final (ownerId, farmId, version, snapshot) = await recordSnapshot(
    db,
    recordType,
    id,
  );
  final previous =
      await (db.select(db.syncMutations)
            ..where(
              (t) =>
                  t.recordId.equals(id) &
                  t.recordType.equals(recordType) &
                  t.ownerId.equals(ownerId) &
                  t.farmId.equals(farmId),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.rowId)])
            ..limit(1))
          .getSingleOrNull();
  final body = jsonEncode(snapshot);
  if (utf8.encode(body).length > 65536) throw StateError('payload_too_large');
  await db
      .into(db.syncMutations)
      .insert(
        SyncMutationsCompanion.insert(
          mutationId: mutationId ?? newUuid(),
          farmId: farmId,
          ownerId: ownerId,
          operation: operation,
          recordType: recordType,
          recordId: id,
          createdAt: at,
          payload: Value(body),
          recordVersion: Value(version),
          dependencyId: Value(previous?.mutationId ?? photoDependency),
        ),
      );
}

/// A record's current row as the outbox snapshots it: owner, farm, version
/// and the fields the transport builds its request from.
///
/// `sectionId` is carried by every record that belongs to a section. The
/// outbox orders on it — a record is never sent before its section — so it is
/// part of the snapshot even for operations whose request has no section.
/// LOCAL-ONLY columns (health score, variety, a task's plan, section notes)
/// are deliberately left out: the server has nowhere to put them.
Future<(String, String, int, Map<String, Object?>)> recordSnapshot(
  AlmanacDatabase db,
  String recordType,
  String id,
) async {
  String? stamp(DateTime? d) => d?.toUtc().toIso8601String();
  switch (recordType) {
    case 'observation':
      final row = await (db.select(
        db.observations,
      )..where((t) => t.id.equals(id))).getSingle();
      return (
        row.ownerId,
        row.farmId,
        row.version,
        {
          'id': row.id,
          'sectionId': row.sectionId,
          'type': row.type,
          'note': row.note,
          'healthStatus': row.healthStatus,
          'actionTaken': row.actionTaken,
          'createdByVoice': row.createdByVoice,
          'localMediaId': row.localMediaId,
          'version': row.version,
          'deletedAt': stamp(row.deletedAt),
        },
      );
    case 'section':
      final row = await (db.select(
        db.sections,
      )..where((t) => t.id.equals(id))).getSingle();
      return (
        row.ownerId,
        row.farmId,
        row.version,
        {
          'id': row.id,
          'name': row.name,
          'areaM2': row.areaM2,
          'boundary': row.boundary == null ? null : jsonDecode(row.boundary!),
          'version': row.version,
          'deletedAt': stamp(row.deletedAt),
        },
      );
    case 'planting':
      final row = await (db.select(
        db.plantings,
      )..where((t) => t.id.equals(id))).getSingle();
      return (
        row.ownerId,
        row.farmId,
        row.version,
        {
          'id': row.id,
          'sectionId': row.sectionId,
          'crop': row.crop,
          'plantedOn': wireDate(row.plantedOn),
          'isCurrent': row.isCurrent,
          'version': row.version,
          'deletedAt': stamp(row.deletedAt),
        },
      );
    case 'farm_task':
      final row = await (db.select(
        db.farmTasks,
      )..where((t) => t.id.equals(id))).getSingle();
      return (
        row.ownerId,
        row.farmId,
        row.version,
        {
          'id': row.id,
          'sectionId': row.sectionId,
          'title': row.title,
          'description': row.description,
          'dueDate': wireDate(row.dueDate),
          'status': row.status,
          'expectedCostCents': row.expectedCostCents,
          'version': row.version,
          'deletedAt': stamp(row.deletedAt),
        },
      );
    case 'financial':
      final row = await (db.select(
        db.financialRecords,
      )..where((t) => t.id.equals(id))).getSingle();
      return (
        row.ownerId,
        row.farmId,
        row.version,
        {
          'id': row.id,
          'sectionId': row.sectionId,
          'type': row.type,
          'category': row.category,
          'amountCents': row.amountCents,
          'date': wireDate(row.date),
          'note': row.note,
          'version': row.version,
          'deletedAt': stamp(row.deletedAt),
        },
      );
    case 'saved_plan':
      final row = await (db.select(
        db.savedPlans,
      )..where((t) => t.id.equals(id))).getSingle();
      return (
        row.ownerId,
        row.farmId,
        row.version,
        {
          'id': row.id,
          'sectionId': row.sectionId,
          'status': row.status,
          'plan': jsonDecode(row.plan),
          'version': row.version,
          'deletedAt': stamp(row.deletedAt),
        },
      );
  }
  throw ArgumentError.value(recordType, 'recordType');
}

/// A server `date`: the calendar day the farmer picked, as `YYYY-MM-DD`.
/// Dates are stored at local midnight, so the local fields are the day —
/// converting to UTC first would move a South African midnight to the day
/// before.
String? wireDate(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
          '${d.month.toString().padLeft(2, '0')}-'
          '${d.day.toString().padLeft(2, '0')}';

/// The section a queued mutation belongs to, from its snapshot: the record
/// itself for a section, the parent section for everything else.
String? sectionOf(SyncMutation row) {
  if (row.recordType == 'section') return row.recordId;
  final payload = row.payload;
  if (payload == null) return null;
  final body = jsonDecode(payload);
  return body is Map ? body['sectionId'] as String? : null;
}

/// One outbox, shared with the farm repository. Scope is fixed for a session.
class SyncOutbox {
  SyncOutbox(this.db, {required this.ownerId, required this.farmId}) {
    if (!isUuid(ownerId) || !isUuid(farmId)) {
      throw ArgumentError('invalid_scope');
    }
  }
  final AlmanacDatabase db;
  final String ownerId;
  final String farmId;

  Expression<bool> _scope($SyncMutationsTable t) =>
      t.ownerId.equals(ownerId) & t.farmId.equals(farmId);

  Stream<List<SyncMutation>> watch() =>
      (db.select(db.syncMutations)..where(_scope)).watch();

  Future<List<SyncMutation>> entries() =>
      (db.select(db.syncMutations)
            ..where(_scope)
            ..orderBy([(t) => OrderingTerm.asc(t.rowId)]))
          .get();

  /// Only call when opening a session, never while another runner owns it.
  Future<void> recover() => db.transaction(() async {
    for (final row in await entries()) {
      if (row.deliveryState != 'syncing') continue;
      await (db.update(
        db.syncMutations,
      )..where((t) => _scope(t) & t.mutationId.equals(row.mutationId))).write(
        SyncMutationsCompanion(
          deliveryState: Value(row.budgetCount >= 8 ? 'failed' : 'pending'),
          errorCode: const Value('interrupted'),
        ),
      );
    }
  });

  /// Rows that may be sent now, in the order they were queued.
  ///
  /// Insertion order alone is not enough: a row that failed, or is waiting
  /// out a backoff, would let the rows behind it overtake. So a row also
  /// waits while any earlier row is still open (unsent, and not superseded
  /// by the server's version) for
  ///
  /// * the same record — edits reach the server in the order they were made;
  /// * its section — a planting, task, plan, observation or photo is never
  ///   sent before the section it belongs to exists on the server;
  /// * any planting in the same section, for a planting — the old planting
  ///   stands down before its replacement claims current, as `acceptPlan`
  ///   queued them, which is what the server's one-current-planting index
  ///   requires.
  ///
  /// A row with no payload is legacy and never sent, so it holds nothing up.
  Future<List<SyncMutation>> _eligible() async {
    final rows = await entries();
    if (rows.any((r) => r.deliveryState == 'syncing')) return [];
    final resolved = {
      for (final r in rows)
        if (r.syncedAt != null || r.deliveryState == 'superseded') r.mutationId,
    };
    // A photo's section is that of the observation carrying it.
    final photoSections = <String, String>{
      for (final r in rows)
        if (r.recordType == 'observation' && r.payload != null)
          if (jsonDecode(r.payload!) case {
            'localMediaId': final String media,
            'sectionId': final String section,
          })
            media: section,
    };
    final open = <String>{};
    final openPlantings = <String>{};
    final eligible = <SyncMutation>[];
    for (final r in rows) {
      final section = r.recordType == 'media'
          ? photoSections[r.recordId]
          : sectionOf(r);
      final ready =
          r.syncedAt == null &&
          r.payload != null &&
          syncedRecordTypes.contains(r.recordType) &&
          r.deliveryState == 'pending' &&
          r.budgetCount < 8 &&
          (r.dependencyId == null || resolved.contains(r.dependencyId)) &&
          !open.contains(r.recordId) &&
          (section == null ||
              section == r.recordId ||
              !open.contains(section)) &&
          !(r.recordType == 'planting' && openPlantings.contains(section));
      if (ready) eligible.add(r);
      if (r.payload != null && !resolved.contains(r.mutationId)) {
        open.add(r.recordId);
        if (r.recordType == 'planting' && section != null) {
          openPlantings.add(section);
        }
      }
    }
    return eligible;
  }

  /// This record's queued changes the server has not taken and has not
  /// overruled — the farmer's work that a pull must not overwrite.
  Future<List<SyncMutation>> unresolved(String recordId) async => [
    for (final r in await entries())
      if (r.recordId == recordId &&
          r.payload != null &&
          r.syncedAt == null &&
          r.deliveryState != 'superseded')
        r,
  ];

  /// The server refused this chain's first change as conflicting and its
  /// version has now replaced the captured chain, including queued successors.
  /// They are never sent; the record reads
  /// "Changed on another phone" until the farmer changes it again.
  Future<void> supersede(String recordId, {required Set<String> mutationIds}) =>
      (db.update(db.syncMutations)..where(
            (t) =>
                _scope(t) &
                t.recordId.equals(recordId) &
                t.mutationId.isIn(mutationIds) &
                t.syncedAt.isNull() &
                t.deliveryState.equals('syncing').not(),
          ))
          .write(
            const SyncMutationsCompanion(deliveryState: Value('superseded')),
          );

  /// Records with a change the server refused as conflicting.
  Future<Map<String, String>> conflicts() async => {
    for (final r in await entries())
      if (r.deliveryState == 'conflict') r.recordId: r.recordType,
  };

  Future<DateTime?> nextDue() async {
    final rows = await _eligible();
    if (rows.isEmpty) return null;
    return rows
        .map((r) => r.nextAttemptAt ?? DateTime.fromMillisecondsSinceEpoch(0))
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Future<SyncMutation?> claim(DateTime now) => db.transaction(() async {
    for (final row in await _eligible()) {
      if (row.nextAttemptAt?.isAfter(now) ?? false) continue;
      final claimed = row.copyWith(
        deliveryState: 'syncing',
        attemptCount: row.attemptCount + 1,
        budgetCount: row.budgetCount + 1,
        errorCode: const Value(null),
      );
      await db.update(db.syncMutations).replace(claimed);
      return claimed;
    }
    return null;
  });

  UpdateStatement<$SyncMutationsTable, SyncMutation> _claim(SyncMutation row) =>
      db.update(db.syncMutations)..where(
        (t) =>
            _scope(t) &
            t.mutationId.equals(row.mutationId) &
            t.deliveryState.equals('syncing') &
            t.attemptCount.equals(row.attemptCount),
      );

  Future<LocalPhoto?> photo(String id) =>
      (db.select(db.localPhotos)..where(
            (t) =>
                t.id.equals(id) &
                t.ownerId.equals(ownerId) &
                t.farmId.equals(farmId),
          ))
          .getSingleOrNull();

  Future<void> acknowledge(SyncMutation row, DateTime at, {String? cloudId}) =>
      db.transaction(() async {
        if (row.recordType == 'media' &&
            (cloudId == null || !isUuid(cloudId))) {
          throw StateError('invalid_ack');
        }
        final changed = await _claim(row).write(
          SyncMutationsCompanion(
            syncedAt: Value(at),
            deliveryState: const Value('synced'),
            errorCode: const Value(null),
          ),
        );
        if (changed != 1) throw StateError('stale_claim');
        if (row.recordType == 'media') {
          final changed =
              await (db.update(db.localPhotos)..where(
                    (t) =>
                        t.id.equals(row.recordId) &
                        t.ownerId.equals(ownerId) &
                        t.farmId.equals(farmId),
                  ))
                  .write(LocalPhotosCompanion(cloudId: Value(cloudId)));
          if (changed != 1) throw StateError('missing_media');
        } else {
          // An edit while the send was in flight must stay pending.
          await markSynced(row.recordType, row.recordId, row.recordVersion!);
        }
      });

  /// The record's own `sync_state`, set to synced only if it is still the
  /// version that was sent.
  Future<void> markSynced(String recordType, String id, int version) =>
      updateRecord(
        db,
        recordType,
        id,
        ownerId: ownerId,
        farmId: farmId,
        version: version,
        values: {'sync_state': const Constant('synced')},
      );

  Future<void> release(
    SyncMutation row,
    String state,
    String code,
    DateTime due, {
    bool refund = false,
  }) async {
    final changed = await _claim(row).write(
      SyncMutationsCompanion(
        deliveryState: Value(state),
        errorCode: Value(code),
        nextAttemptAt: Value(due),
        budgetCount: Value(row.budgetCount - (refund ? 1 : 0)),
      ),
    );
    if (changed != 1) throw StateError('stale_claim');
  }

  /// Conflicts need reconciliation, not blind manual retry.
  ///
  /// For a photo this is also the farmer's consent to server-side recovery of
  /// the attempt that failed: the transport may send one retry request naming
  /// that attempt, and no other.
  Future<void> retry(String mutationId) => db.transaction(() async {
    final changed =
        await (db.update(db.syncMutations)..where(
              (t) =>
                  _scope(t) &
                  t.mutationId.equals(mutationId) &
                  t.deliveryState.equals('failed'),
            ))
            .write(
              const SyncMutationsCompanion(
                deliveryState: Value('pending'),
                budgetCount: Value(0),
                nextAttemptAt: Value(null),
                errorCode: Value(null),
              ),
            );
    if (changed != 1) throw StateError('not_retryable');
    final row = await (db.select(
      db.syncMutations,
    )..where((t) => _scope(t) & t.mutationId.equals(mutationId))).getSingle();
    if (row.recordType == 'media') {
      final media = await photo(row.recordId);
      await _photo(row.recordId).write(
        LocalPhotosCompanion(recoverAttemptId: Value(media?.failedAttemptId)),
      );
    }
  });

  /// Every failed send behind one record — the record's own and the photo it
  /// waits on — made pending again. Returns how many were reset.
  Future<int> retryRecord(String recordId) async {
    final rows = await entries();
    final media = <String>{
      for (final r in rows)
        if (r.recordId == recordId && r.payload != null)
          ?(jsonDecode(r.payload!) as Map<String, dynamic>)['localMediaId']
              as String?,
    };
    var reset = 0;
    for (final r in rows) {
      if (r.deliveryState != 'failed') continue;
      if (r.recordId != recordId && !media.contains(r.recordId)) continue;
      await retry(r.mutationId);
      reset++;
    }
    return reset;
  }

  /// A send that failed for want of a network is due again the moment the
  /// network is back: a backoff chosen while the phone was offline only
  /// delays the farmer. Rate limits and server trouble keep their delay.
  Future<void> expedite() =>
      (db.update(db.syncMutations)..where(
            (t) =>
                _scope(t) &
                t.deliveryState.equals('pending') &
                t.errorCode.equals('network'),
          ))
          .write(const SyncMutationsCompanion(nextAttemptAt: Value(null)));

  UpdateStatement<$LocalPhotosTable, LocalPhoto> _photo(String id) =>
      db.update(db.localPhotos)..where(
        (t) =>
            t.id.equals(id) &
            t.ownerId.equals(ownerId) &
            t.farmId.equals(farmId),
      );

  /// Persisted before anything is sent to storage, so a restart polls the
  /// same upload.
  Future<void> recordUpload(String mediaId, String uploadId) =>
      _photo(mediaId).write(LocalPhotosCompanion(uploadId: Value(uploadId)));

  /// The attempt the server last reported as failed and retryable, or null
  /// once nothing is failed. Also spends any recovery the farmer asked for:
  /// it named one failure, and that failure has now been answered.
  Future<void> recordFailedAttempt(String mediaId, String? attemptId) =>
      _photo(mediaId).write(
        LocalPhotosCompanion(
          failedAttemptId: Value(attemptId),
          recoverAttemptId: const Value(null),
        ),
      );

  /// The section a photo was taken in: that of the observation carrying it.
  Future<String?> mediaSection(String mediaId) async {
    final row =
        await (db.select(db.observations)
              ..where(
                (t) =>
                    t.localMediaId.equals(mediaId) &
                    t.ownerId.equals(ownerId) &
                    t.farmId.equals(farmId),
              )
              ..limit(1))
            .getSingleOrNull();
    return row?.sectionId;
  }

  /// Photos the server holds a ready, cleaned copy of, whose phone copy is
  /// still on disk.
  Future<List<LocalPhoto>> releasable() =>
      (db.select(db.localPhotos)..where(
            (t) =>
                t.ownerId.equals(ownerId) &
                t.farmId.equals(farmId) &
                t.cloudId.isNotNull() &
                t.purgedAt.isNull(),
          ))
          .get();

  Future<void> markReleased(String mediaId, DateTime at) =>
      _photo(mediaId).write(LocalPhotosCompanion(purgedAt: Value(at)));
}

/// Writes [values] to one record of any outbox record type, scoped to its
/// owner and farm — and, given a [version], only while it is still that
/// version. Returns how many rows changed.
Future<int> updateRecord(
  AlmanacDatabase db,
  String recordType,
  String id, {
  required String ownerId,
  required String farmId,
  int? version,
  required Map<String, Expression<Object>> values,
}) {
  Future<int> write<T extends Table, D>(TableInfo<T, D> table) {
    final c = table.columnsByName;
    return (db.update(table)..where((_) {
          var match =
              c['id']!.equals(id) &
              c['owner_id']!.equals(ownerId) &
              c['farm_id']!.equals(farmId);
          if (version != null) match = match & c['version']!.equals(version);
          return match;
        }))
        .write(RawValuesInsertable<D>(values));
  }

  return switch (recordType) {
    'observation' => write(db.observations),
    'section' => write(db.sections),
    'planting' => write(db.plantings),
    'farm_task' => write(db.farmTasks),
    'financial' => write(db.financialRecords),
    'saved_plan' => write(db.savedPlans),
    _ => Future.value(0),
  };
}

/// The local table holding one outbox record type.
TableInfo<Table, dynamic>? recordTable(AlmanacDatabase db, String type) =>
    switch (type) {
      'observation' => db.observations,
      'section' => db.sections,
      'planting' => db.plantings,
      'farm_task' => db.farmTasks,
      'financial' => db.financialRecords,
      'saved_plan' => db.savedPlans,
      _ => null,
    };

bool isUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);
