/// Which farm the phone shows, and whose queue it sends.
///
/// The phone's one database holds two kinds of farm. The **demo seed**
/// (Sipho's Siyakhula Farm) has no user and exists on no server; it is what
/// a signed-out phone shows, and nothing written to it is ever sent. An
/// **account farm** is the signed-in farmer's own, named by `GET /farms`, and
/// stored locally under that farmer's user id.
///
/// The separation is by ownership, not by a flag: every local row carries an
/// `owner_id`, the demo's is a fixed constant no server account can hold,
/// the sync queue only ever claims rows whose owner and farm match the
/// signed-in session, and the screens only read rows of the active
/// [FarmScope]. So a record made while signed out stays in the demo farm
/// for good — it is never re-owned and uploaded under whoever signs in next.
library;

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';

import '../../domain/auth/auth_models.dart';
import '../local/database.dart';
import '../local/seed.dart';
import '../local/sync_outbox.dart';
import 'api_sync_transport.dart';

class FarmScope {
  const FarmScope({
    required this.ownerId,
    required this.farmId,
    required this.isAccount,
  });

  final String ownerId;
  final String farmId;

  /// False for the demo seed.
  final bool isAccount;

  static const demo = FarmScope(
    ownerId: DemoSeed.ownerId,
    farmId: DemoSeed.farmId,
    isAccount: false,
  );

  @override
  bool operator ==(Object other) =>
      other is FarmScope &&
      other.ownerId == ownerId &&
      other.farmId == farmId &&
      other.isAccount == isAccount;

  @override
  int get hashCode => Object.hash(ownerId, farmId, isAccount);
}

class AccountWorkspace {
  AccountWorkspace(this.db, this.request, {DateTime Function()? now})
    : now = now ?? DateTime.now;

  final AlmanacDatabase db;
  final AuthorizedRequest request;
  final DateTime Function() now;

  /// The account's farm as a previous sign-in left it on this phone, so a
  /// farmer who opens the app with no signal still sees their own farm.
  Future<FarmScope?> local(AuthUser user) async {
    if (!_accountIds(user.id)) return null;
    final farm =
        await (db.select(db.farms)
              ..where((t) => t.ownerId.equals(user.id) & t.deletedAt.isNull())
              ..limit(1))
            .getSingleOrNull();
    return farm == null ? null : _scope(user.id, farm.id);
  }

  /// Asks the server which farm is this account's, stores it, and pulls its
  /// sections. Null when the account has no farm yet. Throws on a network or
  /// server failure; the caller keeps whatever [local] had.
  Future<FarmScope?> refresh(AuthUser user) async {
    if (!_accountIds(user.id)) return null;
    final page = _object((await _get('/farms')).data);
    final items = page['items'];
    if (items is! List || items.isEmpty) return local(user);
    final farm = _object(items.first);
    final farmId = _string(farm, 'id');
    if (_string(farm, 'owner_id') != user.id || !_accountIds(farmId)) {
      throw const FormatException('farm_scope');
    }

    await db.transaction(() async {
      await db
          .into(db.users)
          .insertOnConflictUpdate(
            UsersCompanion.insert(
              id: user.id,
              displayName: '${user.firstName} ${user.surname}'.trim(),
              createdAt: now(),
            ),
          );
      await db
          .into(db.farms)
          .insertOnConflictUpdate(
            FarmsCompanion.insert(
              id: farmId,
              farmId: farmId,
              ownerId: user.id,
              name: _string(farm, 'name'),
              version: Value(_int(farm, 'version')),
              syncState: const Value('synced'),
              createdAt: _date(farm, 'created_at'),
              updatedAt: _date(farm, 'updated_at'),
            ),
          );
    });
    await _pullSections(user.id, farmId);
    return _scope(user.id, farmId);
  }

  /// Sections the server has, into the phone. A section with an unsent local
  /// change keeps the phone's version until that change is delivered; a
  /// synced section the server no longer lists is tombstoned here too.
  Future<void> _pullSections(String ownerId, String farmId) async {
    final seen = <String>{};
    final pulled = <Map<String, Object?>>[];
    String? cursor;
    do {
      final query = {'limit': '100', 'cursor': ?cursor};
      final page = _object(
        (await _get(
          Uri(
            path: '/farms/$farmId/sections',
            queryParameters: query,
          ).toString(),
        )).data,
      );
      final items = page['items'];
      if (items is! List) throw const FormatException('sections');
      for (final item in items) {
        final section = _object(item);
        if (_string(section, 'owner_id') != ownerId ||
            _string(section, 'farm_id') != farmId) {
          throw const FormatException('section_scope');
        }
        seen.add(_string(section, 'id'));
        pulled.add(section);
      }
      final next = page['next_cursor'];
      cursor = next is String && next.isNotEmpty ? next : null;
    } while (cursor != null);

    await db.transaction(() async {
      final existing = {
        for (final row
            in await (db.select(db.sections)..where(
                  (t) => t.ownerId.equals(ownerId) & t.farmId.equals(farmId),
                ))
                .get())
          row.id: row,
      };
      for (final section in pulled) {
        final id = _string(section, 'id');
        final mine = existing[id];
        if (mine != null && mine.syncState != 'synced') continue;
        final boundary = section['boundary'];
        final area = section['area_m2'];
        await db
            .into(db.sections)
            .insertOnConflictUpdate(
              SectionsCompanion.insert(
                id: id,
                farmId: farmId,
                ownerId: ownerId,
                name: _string(section, 'name'),
                boundary: Value(boundary == null ? null : jsonEncode(boundary)),
                // `Numeric(14, 2)`, a string on the wire; kept a string.
                areaM2: Value(
                  area == null
                      ? null
                      : area is num
                      ? area.toStringAsFixed(2)
                      : '$area',
                ),
                version: Value(_int(section, 'version')),
                syncState: const Value('synced'),
                createdAt: _date(section, 'created_at'),
                updatedAt: _date(section, 'updated_at'),
              ),
            );
      }
      for (final row in existing.values) {
        if (seen.contains(row.id) ||
            row.syncState != 'synced' ||
            row.deletedAt != null) {
          continue;
        }
        await (db.update(db.sections)..where((t) => t.id.equals(row.id))).write(
          SectionsCompanion(deletedAt: Value(now())),
        );
      }
    });
  }

  Future<Response<Object?>> _get(String path) async {
    final response = await request('GET', path);
    final status = response.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw failureFor(status, response.data, response.headers);
    }
    return response;
  }

  FarmScope _scope(String ownerId, String farmId) =>
      FarmScope(ownerId: ownerId, farmId: farmId, isAccount: true);
}

/// An id a real account can hold. The demo seed's ids are refused outright:
/// they are constants in this app's source, and a server that ever answered
/// with one would otherwise pull the demo farm's records into its queue.
bool _accountIds(String id) =>
    isUuid(id) && id != DemoSeed.ownerId && id != DemoSeed.farmId;

Map<String, Object?> _object(Object? data) {
  if (data is Map) return data.cast<String, Object?>();
  throw const FormatException('object');
}

String _string(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw FormatException(key);
}

int _int(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is int) return value;
  throw FormatException(key);
}

DateTime _date(Map<String, Object?> json, String key) =>
    DateTime.tryParse(_string(json, key)) ?? (throw FormatException(key));
