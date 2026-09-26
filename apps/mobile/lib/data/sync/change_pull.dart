/// Brings edits made on another phone onto this one.
///
/// Reads the farm's change feed (`GET /farms/{farm_id}/changes`, see
/// docs/farm-records-api.md) forward from where this phone last stopped. The
/// feed names a record, its operation and its new version — never its
/// fields — so each record that moved is fetched and written locally.
///
/// **Conflicts.** The phone's own unsent work is never overwritten:
///
/// * A record with a queued change that is still on its way (queued,
///   sending, or "not sent yet") keeps the phone's version. If the server's
///   copy moved in the meantime, that send carries a stale
///   `expected_version` and the server refuses it with 409 — the outbox row
///   becomes a conflict.
/// * A record whose queued change the server refused as a conflict takes
///   the server's version: the other phone's edit reached the server first,
///   and sending ours as-is would overwrite it. The refused change and its
///   queued successors are marked `superseded` — never sent — and the record
///   reads "Changed on another phone" until the farmer edits it again, which then goes up against the
///   server's version.
/// * Everything else follows the server whenever the server's version is
///   newer than the phone's. Fields only the phone has (health score,
///   variety, a task's plan, section notes) are left as they were.
///
/// Conflicted records are reconciled on every pull, not only when the feed
/// mentions them, so a conflict whose change the cursor has already passed
/// is still resolved.
library;

import 'dart:convert';

import 'package:dio/dio.dart' show Response;
import 'package:drift/drift.dart';

import '../local/database.dart';
import '../local/sync_outbox.dart';
import 'api_sync_transport.dart';

class ChangePuller {
  ChangePuller(
    this.db,
    this.request, {
    required this.outbox,
    DateTime Function()? now,
    this.pageSize = 100,
    this.onError,
  }) : now = now ?? DateTime.now;

  final AlmanacDatabase db;
  final AuthorizedRequest request;
  final SyncOutbox outbox;
  final DateTime Function() now;
  final int pageSize;

  /// Fixed diagnostic codes only — never a record, token or path.
  final void Function(String code)? onError;

  String get _ownerId => outbox.ownerId;
  String get _farmId => outbox.farmId;
  String get _farm => '/farms/$_farmId';

  /// The feed's record types, as this phone names them. Anything else in the
  /// feed (the farm itself, photo metadata) has no local counterpart to
  /// update and is passed over.
  static const localTypes = {
    'section': 'section',
    'planting': 'planting',
    'observation': 'observation',
    'task': 'farm_task',
    'financial': 'financial',
    'plan': 'saved_plan',
  };

  static const _resources = {
    'section': 'sections',
    'planting': 'plantings',
    'observation': 'observations',
    'farm_task': 'tasks',
    'financial': 'financials',
    'saved_plan': 'plans',
  };

  /// Reads the feed to its end, then settles every conflicted record.
  /// Returns how many records were written. Throws on a network or server
  /// failure; the cursor stays at the last page fully applied. Deferred
  /// records also hold the durable cursor back, including across restarts.
  Future<int> pull() async {
    var applied = 0;
    var since = await _cursor();
    var deferred = false;
    while (true) {
      final page = _object(
        (await _get(
          Uri(
            path: '$_farm/changes',
            queryParameters: {'since': '$since', 'limit': '$pageSize'},
          ).toString(),
        )).data,
      );
      final items = page['items'];
      if (items is! List) throw const FormatException('changes');
      // One fetch per record per page: only its latest change matters, and
      // records are applied in the order of those latest changes — the order
      // the server accepted them in, which is what keeps a stand-down
      // planting ahead of its replacement.
      final latest = <String, _Change>{};
      var last = since;
      for (final item in items) {
        final change = _Change.parse(_object(item));
        if (change.cursor <= last) throw const FormatException('cursor');
        last = change.cursor;
        final type = localTypes[change.recordType];
        if (type == null) continue;
        latest.remove(change.recordId);
        latest[change.recordId] = change;
      }
      for (final change in latest.values) {
        final result = await _settle(
          localTypes[change.recordType]!,
          change.recordId,
          version: change.version,
          deleted: change.operation == 'delete',
        );
        if (result == _Settlement.applied) applied++;
        if (result == _Settlement.deferred) deferred = true;
      }
      if (last > since) {
        since = last;
        // Continue scanning so a later dependency can still be reconciled,
        // but never checkpoint past work that must be tried on the next pull.
        if (!deferred) await _saveCursor(since);
      }
      if (page['next_cursor'] == null || items.isEmpty) break;
    }
    for (final entry in (await outbox.conflicts()).entries) {
      if (await _settle(entry.value, entry.key) == _Settlement.applied) {
        applied++;
      }
    }
    await _markPulled();
    return applied;
  }

  /// Writes the server's copy of one record, unless the phone holds work
  /// on it the server has not seen. Deferred records must remain in the feed.
  Future<_Settlement> _settle(
    String type,
    String id, {
    int? version,
    bool deleted = false,
  }) async {
    final table = recordTable(db, type);
    if (table == null) return _Settlement.unchanged;
    final local = await _local(table, id);
    if (local != null && !local.ours(_ownerId, _farmId)) {
      return _Settlement.unchanged;
    }
    final open = await outbox.unresolved(id);
    if (open.isNotEmpty &&
        (open.first.deliveryState != 'conflict' ||
            open.any((r) => r.deliveryState == 'syncing'))) {
      return _Settlement.deferred;
    }
    final mutationIds = open.map((r) => r.mutationId).toSet();
    final conflicted = open.isNotEmpty;
    if (!conflicted &&
        local != null &&
        version != null &&
        version <= local.version) {
      return _Settlement.unchanged; // Often this phone's own change.
    }
    final Map<String, Object?>? server;
    try {
      server = deleted && !conflicted ? null : await _fetch(type, id);
    } on _Unapplicable {
      onError?.call('pull_record_invalid');
      return _Settlement.deferred;
    }
    if (server == null && local == null) return _Settlement.unchanged;
    try {
      return await db.transaction(() async {
        // Re-checked inside the write: the farmer may have edited the
        // record while it was being fetched.
        final still = await outbox.unresolved(id);
        if (still.length != mutationIds.length ||
            still.any(
              (r) =>
                  !mutationIds.contains(r.mutationId) ||
                  r.deliveryState == 'syncing',
            )) {
          return _Settlement.deferred;
        }
        final mine = await _local(table, id);
        if (server == null) {
          if (mine == null) return _Settlement.unchanged;
          if (mine.deleted) {
            await outbox.supersede(id, mutationIds: mutationIds);
            return still.isNotEmpty
                ? _Settlement.applied
                : _Settlement.unchanged;
          }
          await updateRecord(
            db,
            type,
            id,
            ownerId: _ownerId,
            farmId: _farmId,
            values: {
              'deleted_at': Variable<DateTime>(now()),
              'version': Variable<int>(
                version != null && version > mine.version
                    ? version
                    : mine.version,
              ),
              'sync_state': const Constant('synced'),
            },
          );
        } else {
          final serverVersion = server['version']! as int;
          if (still.isEmpty && mine != null && serverVersion <= mine.version) {
            return _Settlement.unchanged;
          }
          if (!await _write(type, id, server, exists: mine != null)) {
            throw const _Unapplicable();
          }
        }
        await outbox.supersede(id, mutationIds: mutationIds);
        return _Settlement.applied;
      });
    } on Object {
      // A server record the phone cannot hold as-is — most often a second
      // current planting while this phone's own replan is still unsent. It
      // is left for the next pull rather than stopping this one.
      onError?.call('pull_record_skipped');
      return _Settlement.deferred;
    }
  }

  /// The record as the server holds it now, or null once it is gone —
  /// tombstoned, or in a section that is.
  Future<Map<String, Object?>?> _fetch(String type, String id) async {
    final response = await request('GET', '$_farm/${_resources[type]}/$id');
    final status = response.statusCode ?? 0;
    if (status == 404) return null;
    if (status < 200 || status >= 300) {
      throw failureFor(status, response.data, response.headers);
    }
    var body = _object(response.data);
    // `GET …/sections/{id}` answers with the section's detail page.
    if (type == 'section') body = _object(body['section']);
    if (body['id'] != id ||
        body['owner_id'] != _ownerId ||
        body['farm_id'] != _farmId ||
        body['version'] is! int) {
      throw const _Unapplicable();
    }
    return body;
  }

  /// Server fields only. Columns the server does not have are not touched
  /// on an existing row, and start empty on a new one.
  Future<bool> _write(
    String type,
    String id,
    Map<String, Object?> s, {
    required bool exists,
  }) async {
    final version = Value(s['version']! as int);
    const synced = Value('synced');
    final created = Value(_time(s['created_at']));
    final updated = Value(_time(s['updated_at']));
    Future<void> put<T extends Table, D>(
      TableInfo<T, D> table,
      Insertable<D> row,
    ) async {
      if (exists) {
        await (db.update(table)..where(_byId(table, id))).write(row);
      } else {
        await db.into(table).insert(row);
      }
    }

    switch (type) {
      case 'section':
        final area = s['area_m2'];
        await put(
          db.sections,
          SectionsCompanion(
            id: Value(id),
            farmId: Value(_farmId),
            ownerId: Value(_ownerId),
            name: Value(s['name']! as String),
            boundary: Value(
              s['boundary'] == null ? null : jsonEncode(s['boundary']),
            ),
            areaM2: Value(
              area == null
                  ? null
                  : area is num
                  ? area.toStringAsFixed(2)
                  : '$area',
            ),
            version: version,
            syncState: synced,
            createdAt: created,
            updatedAt: updated,
            deletedAt: const Value(null),
          ),
        );
      case 'planting':
        final section = s['section_id']! as String;
        if (s['is_current'] == true) {
          // The server holds one current planting per section, so no other
          // can be current there. One the farmer has unsent work on cannot
          // be stood down under them: the whole record waits instead.
          final others =
              await (db.select(db.plantings)..where(
                    (t) =>
                        t.sectionId.equals(section) &
                        t.ownerId.equals(_ownerId) &
                        t.farmId.equals(_farmId) &
                        t.isCurrent.equals(true) &
                        t.deletedAt.isNull() &
                        t.id.equals(id).not(),
                  ))
                  .get();
          for (final other in others) {
            if ((await outbox.unresolved(other.id)).isNotEmpty) return false;
            await (db.update(db.plantings)..where(
                  (t) =>
                      t.id.equals(other.id) &
                      t.ownerId.equals(_ownerId) &
                      t.farmId.equals(_farmId),
                ))
                .write(const PlantingsCompanion(isCurrent: Value(false)));
          }
        }
        await put(
          db.plantings,
          PlantingsCompanion(
            id: Value(id),
            farmId: Value(_farmId),
            ownerId: Value(_ownerId),
            sectionId: Value(section),
            crop: Value(s['crop']! as String),
            plantedOn: Value(_day(s['planted_on'])),
            isCurrent: Value(s['is_current'] == true),
            version: version,
            syncState: synced,
            createdAt: created,
            updatedAt: updated,
            deletedAt: const Value(null),
          ),
        );
      case 'observation':
        await put(
          db.observations,
          ObservationsCompanion(
            id: Value(id),
            farmId: Value(_farmId),
            ownerId: Value(_ownerId),
            sectionId: Value(s['section_id']! as String),
            type: Value(s['type']! as String),
            note: Value(s['note']! as String),
            healthStatus: Value(s['health_status'] as String?),
            actionTaken: Value(s['action_taken'] as String?),
            createdByVoice: Value(s['created_by_voice'] == true),
            version: version,
            syncState: synced,
            createdAt: created,
            updatedAt: updated,
            deletedAt: const Value(null),
          ),
        );
      case 'farm_task':
        await put(
          db.farmTasks,
          FarmTasksCompanion(
            id: Value(id),
            farmId: Value(_farmId),
            ownerId: Value(_ownerId),
            sectionId: Value(s['section_id']! as String),
            title: Value(s['title']! as String),
            description: Value(s['description'] as String?),
            dueDate: Value(_day(s['due_date'])!),
            status: Value(s['status']! as String),
            expectedCostCents: Value(s['expected_cost_cents'] as int?),
            version: version,
            syncState: synced,
            createdAt: created,
            updatedAt: updated,
            deletedAt: const Value(null),
          ),
        );
      case 'financial':
        await put(
          db.financialRecords,
          FinancialRecordsCompanion(
            id: Value(id),
            farmId: Value(_farmId),
            ownerId: Value(_ownerId),
            sectionId: Value(s['section_id'] as String?),
            type: Value(s['type']! as String),
            category: Value(s['category']! as String),
            amountCents: Value(s['amount_cents']! as int),
            date: Value(_day(s['date'])!),
            note: Value(s['note'] as String?),
            version: version,
            syncState: synced,
            createdAt: created,
            updatedAt: updated,
            deletedAt: const Value(null),
          ),
        );
      case 'saved_plan':
        final status = s['status']! as String;
        final previous = exists
            ? await (db.select(
                db.savedPlans,
              )..where((t) => t.id.equals(id))).getSingleOrNull()
            : null;
        await put(
          db.savedPlans,
          SavedPlansCompanion(
            id: Value(id),
            farmId: Value(_farmId),
            ownerId: Value(_ownerId),
            sectionId: Value(s['section_id']! as String),
            status: Value(status),
            plan: Value(jsonEncode(s['plan'])),
            // `PlanView` has no approval time; the update that approved it
            // is the closest the phone can know.
            approvedAt: Value(
              status == 'approved'
                  ? previous?.approvedAt ?? _time(s['updated_at'])
                  : null,
            ),
            version: version,
            syncState: synced,
            createdAt: created,
            updatedAt: updated,
            deletedAt: const Value(null),
          ),
        );
      default:
        return false;
    }
    return true;
  }

  Expression<bool> Function(Table) _byId(
    TableInfo<Table, dynamic> table,
    String id,
  ) =>
      (_) =>
          table.columnsByName['id']!.equals(id) &
          table.columnsByName['owner_id']!.equals(_ownerId) &
          table.columnsByName['farm_id']!.equals(_farmId);

  Future<_Local?> _local(TableInfo<Table, dynamic> table, String id) async {
    final c = table.columnsByName;
    final columns = [
      c['version']!,
      c['owner_id']!,
      c['farm_id']!,
      c['deleted_at']!,
    ];
    final row =
        await (db.selectOnly(table)
              ..addColumns(columns)
              ..where(c['id']!.equals(id)))
            .getSingleOrNull();
    if (row == null) return null;
    return _Local(
      version: row.read(columns[0])! as int,
      ownerId: row.read(columns[1])! as String,
      farmId: row.read(columns[2])! as String,
      deleted: row.read(columns[3]) != null,
    );
  }

  Future<int> _cursor() async =>
      (await (db.select(db.syncCursors)..where(
                (t) => t.ownerId.equals(_ownerId) & t.farmId.equals(_farmId),
              ))
              .getSingleOrNull())
          ?.cursor ??
      0;

  /// Stamps a pull that read the feed to its end. The durable cursor is
  /// re-read rather than passed in: a deferred record holds it back, and this
  /// must not move it.
  Future<void> _markPulled() async => db
      .into(db.syncCursors)
      .insertOnConflictUpdate(
        SyncCursorsCompanion.insert(
          ownerId: _ownerId,
          farmId: _farmId,
          cursor: await _cursor(),
          pulledAt: Value(now()),
        ),
      );

  Future<void> _saveCursor(int cursor) => db
      .into(db.syncCursors)
      .insertOnConflictUpdate(
        SyncCursorsCompanion.insert(
          ownerId: _ownerId,
          farmId: _farmId,
          cursor: cursor,
        ),
      );

  Future<Response<Object?>> _get(String path) async {
    final response = await request('GET', path);
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw failureFor(status, response.data, response.headers);
    }
    return response;
  }
}

enum _Settlement { unchanged, applied, deferred }

class _Local {
  const _Local({
    required this.version,
    required this.ownerId,
    required this.farmId,
    required this.deleted,
  });
  final int version;
  final String ownerId, farmId;
  final bool deleted;

  bool ours(String owner, String farm) => ownerId == owner && farmId == farm;
}

/// `ChangeView`.
class _Change {
  const _Change(
    this.cursor,
    this.recordType,
    this.recordId,
    this.operation,
    this.version,
  );

  factory _Change.parse(Map<String, Object?> json) {
    final cursor = json['cursor'];
    final type = json['record_type'];
    final id = json['record_id'];
    final operation = json['operation'];
    final version = json['version'];
    if (cursor is! int ||
        type is! String ||
        id is! String ||
        !isUuid(id) ||
        operation is! String ||
        version is! int) {
      throw const FormatException('change');
    }
    return _Change(cursor, type, id, operation, version);
  }

  final int cursor;
  final String recordType, recordId, operation;
  final int version;
}

class _Unapplicable implements Exception {
  const _Unapplicable();
}

Map<String, Object?> _object(Object? data) {
  if (data is Map) return data.cast<String, Object?>();
  throw const FormatException('object');
}

DateTime _time(Object? value) =>
    DateTime.tryParse('$value') ?? (throw const _Unapplicable());

/// A server `date` at local midnight, as the phone stores days.
DateTime? _day(Object? value) {
  if (value == null) return null;
  final d = DateTime.tryParse('$value') ?? (throw const _Unapplicable());
  return DateTime(d.year, d.month, d.day);
}
