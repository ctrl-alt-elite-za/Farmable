import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/utils/ids.dart';
import 'database.dart';

/// Called inside the same transaction as the observation write. Preserve the
/// exact version being sent; reading the latest row during a retry is unsafe.
Future<void> enqueueObservation(
  AlmanacDatabase db,
  String id,
  String operation,
  DateTime at, {
  String? mutationId,
  String? photoDependency,
}) async {
  final row = await (db.select(
    db.observations,
  )..where((t) => t.id.equals(id))).getSingle();
  final previous =
      await (db.select(db.syncMutations)
            ..where(
              (t) =>
                  t.recordId.equals(id) &
                  t.recordType.equals('observation') &
                  t.ownerId.equals(row.ownerId) &
                  t.farmId.equals(row.farmId),
            )
            ..orderBy([(t) => OrderingTerm.desc(t.rowId)])
            ..limit(1))
          .getSingleOrNull();
  final body = jsonEncode({
    'id': row.id,
    'sectionId': row.sectionId,
    'type': row.type,
    'note': row.note,
    'healthStatus': row.healthStatus,
    'actionTaken': row.actionTaken,
    'createdByVoice': row.createdByVoice,
    'localMediaId': row.localMediaId,
    'version': row.version,
    'deletedAt': row.deletedAt?.toUtc().toIso8601String(),
  });
  if (utf8.encode(body).length > 65536) throw StateError('payload_too_large');
  await db
      .into(db.syncMutations)
      .insert(
        SyncMutationsCompanion.insert(
          mutationId: mutationId ?? newUuid(),
          farmId: row.farmId,
          ownerId: row.ownerId,
          operation: operation,
          recordType: 'observation',
          recordId: row.id,
          createdAt: at,
          payload: Value(body),
          recordVersion: Value(row.version),
          dependencyId: Value(previous?.mutationId ?? photoDependency),
        ),
      );
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

  Future<List<SyncMutation>> _eligible() async {
    final rows = await entries();
    if (rows.any((r) => r.deliveryState == 'syncing')) return [];
    final synced = rows
        .where((r) => r.syncedAt != null)
        .map((r) => r.mutationId)
        .toSet();
    return rows
        .where(
          (r) =>
              r.syncedAt == null &&
              r.payload != null &&
              const ['observation', 'media'].contains(r.recordType) &&
              r.deliveryState == 'pending' &&
              r.budgetCount < 8 &&
              (r.dependencyId == null || synced.contains(r.dependencyId)),
        )
        .toList();
  }

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
          await (db.update(db.observations)..where(
                (t) =>
                    t.id.equals(row.recordId) &
                    t.ownerId.equals(ownerId) &
                    t.farmId.equals(farmId) &
                    t.version.equals(row.recordVersion!),
              ))
              .write(const ObservationsCompanion(syncState: Value('synced')));
        }
      });

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
  Future<void> retry(String mutationId) async {
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
  }
}

bool isUuid(String value) => RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
).hasMatch(value);
