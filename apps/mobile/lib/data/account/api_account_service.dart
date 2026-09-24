/// The real [AccountService]: `/account/profile`, `/account/farm`,
/// `/account/export` and `DELETE /account`, through the session
/// [ApiAuthService] holds.
///
/// ## Offline edits
///
/// A change the farmer makes is written to the phone first, as a pending
/// edit, and only then sent. With no signal it stays pending — shown as such
/// — and goes out on the next launch or the next visit to Profile with one.
/// The record lives in secure storage under its own key (`almanac.account`),
/// because a profile is personal data even though it is not a credential.
///
/// ## Whose record this is
///
/// The record is stamped with the account it belongs to. If it was written
/// for someone else — a previous farmer on a shared phone whose sign-out did
/// not finish clearing it — it is discarded unread rather than shown to the
/// wrong person or sent under the wrong session.
///
/// Stamping the record is not enough on its own: an operation can start for
/// one account and finish after another has logged in. So every operation
/// captures the account and the session generation it began with (`_Op`),
/// every request it sends is refused once that generation moves, and every
/// write it makes is refused once either has changed.
library;

import 'package:dio/dio.dart';

import '../../domain/account/account_models.dart';
import '../../domain/account/account_service.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/api_auth_service.dart';
import '../auth/session_storage.dart';
import '../device_wipe.dart';
import 'export_store.dart';

class ApiAccountService implements AccountService {
  final ApiAuthService _auth;
  final SessionStorage _storage;
  final ExportStore _exports;
  final DeviceWipe _wipe;
  final DateTime Function() now;

  ApiAccountService(
    this._auth,
    this._storage,
    this._exports,
    this._wipe, {
    this.now = DateTime.now,
  });

  @override
  Future<AccountSnapshot?> cached() async {
    final user = await _signedInUser();
    if (user == null) return null;
    return _snapshot(user, await _record(user));
  }

  @override
  Future<AccountSnapshot?> refresh() async {
    final op = await _begin();
    if (op == null) return null;

    try {
      await _flush(op);
      final profile = await _get(op, '/account/profile');
      Map<String, Object?>? farm;
      try {
        farm = await _get(op, '/account/farm');
      } on AuthException catch (e) {
        // An account whose farm has gone still has a profile to show.
        if (e.failure != AuthFailure.gone) rethrow;
      }
      await _update(
        op,
        (record) => {...record, 'profile': profile, 'farm': farm},
      );
    } on AuthException catch (e) {
      if (e.failure != AuthFailure.offline) rethrow;
    }
    return cached();
  }

  @override
  Future<void> syncPending() async {
    final op = await _begin();
    if (op == null) return;
    if (_pending(await _record(op.user)).isEmpty) return;
    try {
      await _flush(op);
    } on AuthException {
      // Launch is not the place to report this. Profile shows the edit as
      // still waiting, and says why if sending it fails again there.
    }
  }

  @override
  Future<AccountSnapshot> updateDetails({
    String? firstName,
    String? surname,
    AppLanguage? language,
    String? farmName,
  }) async {
    final op = await _require();
    await _update(
      op,
      (record) => {
        ...record,
        'pending': {
          ..._pending(record),
          if (firstName != null) 'first_name': firstName.trim(),
          if (surname != null) 'surname': surname.trim(),
          if (language != null) 'preferred_language': language.name,
          if (farmName != null) 'farm_name': farmName.trim(),
        },
      },
    );

    try {
      await _flush(op);
    } on AuthException catch (e) {
      if (e.failure != AuthFailure.offline) rethrow;
    }
    return await cached() ??
        (throw const AuthException(AuthFailure.invalidSession));
  }

  /// Kept on this phone only. The backend has no consent endpoint yet, so
  /// there is nothing to send it to.
  @override
  Future<AccountSnapshot> setConsent({required bool externalProcessing}) async {
    final op = await _require();
    await _update(
      op,
      (record) => {
        ...record,
        'consent': ConsentChoices(
          externalProcessing: externalProcessing,
          decidedAt: now().toUtc(),
        ).toJson(),
      },
    );
    return await cached() ??
        (throw const AuthException(AuthFailure.invalidSession));
  }

  /// The copy on this phone - but only if it is the signed-in account's.
  ///
  /// The file itself carries no owner; the account record does, under
  /// `export`, and that record is stamped with its owner and cleared on
  /// log-out. A file with no matching entry in the current account's record
  /// belongs to someone else, or to nobody still here, and is deleted rather
  /// than offered.
  @override
  Future<ExportFile?> currentExport() async {
    final file = await _exports.current();
    if (file == null) return null;

    final user = await _signedInUser();
    final ours =
        user != null &&
        (await _record(user))['export'] is Map &&
        !file.isExpiredAt(now());
    if (!ours) {
      await _exports.clear();
      return null;
    }
    return file;
  }

  /// Saved only if the account and session that asked are still the ones on
  /// this phone when the file arrives. A download that outlives a log-out
  /// must not put the last farmer's data back after it was cleared.
  @override
  Future<ExportFile> export(ExportFormat format) async {
    final op = await _require();
    final response = await _auth.authorized(
      'GET',
      '/account/export',
      query: {'format': format.name},
      responseType: ResponseType.bytes,
      generation: op.generation,
    );
    throwUnlessSuccess(response);
    final bytes = response.data;
    if (bytes is! List<int> || bytes.isEmpty) {
      throw const AuthException(AuthFailure.unknown);
    }

    await _ensureCurrent(op);
    final ExportFile file;
    try {
      file = await _exports.save(bytes, format, now());
    } on Object {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
    try {
      await _update(
        op,
        (record) => {
          ...record,
          'export': {'created_at': file.createdAt.toUtc().toIso8601String()},
        },
      );
    } on AuthException {
      // The account changed while the file was being written, or its record
      // would not take the entry. Either way the file is nobody's: remove it.
      await _exports.clear();
      rethrow;
    }
    return file;
  }

  @override
  Future<void> removeExport() async {
    try {
      await _exports.clear();
    } on Object {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
  }

  /// Once the server has deleted the account, that outcome is committed:
  /// nothing after it can turn into "nothing was deleted". Local access ends
  /// first - in memory even if the write fails - then every part of the wipe
  /// is attempted, and the result says whether the phone is clean.
  @override
  Future<DeletionOutcome> deleteAccount({required String password}) async {
    final op = await _require();
    final response = await _auth.authorized(
      'DELETE',
      '/account',
      data: {'password': password},
      generation: op.generation,
    );
    throwUnlessSuccess(response);

    var cleared = true;
    try {
      await _auth.endSessionLocally();
    } on Object {
      cleared = false;
    }
    try {
      if (!await _wipe.run()) cleared = false;
    } on Object {
      cleared = false;
    }
    return cleared ? DeletionOutcome.complete : DeletionOutcome.phoneNotCleared;
  }

  @override
  Future<void> forget() async {
    try {
      await _storage.clear();
    } on Object {
      // Sign-out has already ended the session; a record left behind is
      // stamped with its owner and never shown to anyone else.
    }
    try {
      await _exports.clear();
    } on Object {
      // As above: with no record naming it, currentExport deletes it on sight.
    }
  }

  // ------------------------------------------------------------------ guts

  Future<AuthUser?> _signedInUser() async => switch (await _auth.restore()) {
    SignedIn(session: final session) => session.user,
    _ => null,
  };

  /// Starts an operation for whoever is signed in now, remembering which
  /// account and which session that was.
  Future<_Op?> _begin() async {
    final generation = _auth.generation;
    final user = await _signedInUser();
    if (user == null || generation != _auth.generation) return null;
    return _Op(user, generation);
  }

  Future<_Op> _require() async =>
      await _begin() ?? (throw const AuthException(AuthFailure.invalidSession));

  /// Throws unless [op]'s account and session are still the ones here.
  Future<void> _ensureCurrent(_Op op) async {
    final user = await _signedInUser();
    if (op.generation != _auth.generation || user?.id != op.user.id) {
      throw const AuthException(AuthFailure.invalidSession);
    }
  }

  /// The record, if it is this user's. Anyone else's reads as empty.
  Future<Map<String, Object?>> _record(AuthUser user) async {
    final record = await _storage.read();
    if (record == null || record['owner'] != user.id) return {};
    return record;
  }

  /// Read, change and write [op]'s record - refused if the account or session
  /// has changed since [op] began, so a late answer never writes into a
  /// record that was cleared, or that now belongs to someone else.
  Future<void> _update(
    _Op op,
    Map<String, Object?> Function(Map<String, Object?> record) change,
  ) async {
    await _ensureCurrent(op);
    final next = change(await _record(op.user));
    await _ensureCurrent(op);
    try {
      await _storage.write({...next, 'owner': op.user.id});
    } on SessionStorageException {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
  }

  Map<String, Object?> _pending(Map<String, Object?> record) {
    final raw = record['pending'];
    return raw is Map ? raw.cast<String, Object?>() : {};
  }

  /// Sends [op]'s pending edits, profile then farm, every request bound to
  /// [op]'s session. If the account changes part-way, the rest is abandoned:
  /// the next account's farm must never receive the last one's farm name.
  ///
  /// Each part is cleared from the pending set once the server accepts it;
  /// one the server rejects as invalid is cleared too - it will never be
  /// accepted - and the rejection is reported so the farmer knows.
  Future<void> _flush(_Op op) async {
    final pending = _pending(await _record(op.user));
    if (pending.isEmpty) return;

    final profilePatch = {
      for (final key in const ['first_name', 'surname', 'preferred_language'])
        if (pending.containsKey(key)) key: pending[key],
    };
    if (profilePatch.isNotEmpty) {
      final Map<String, Object?> profile;
      try {
        profile = await _patch(op, '/account/profile', profilePatch);
      } on AuthException catch (e) {
        if (e.failure == AuthFailure.rejected) {
          await _drop(op, profilePatch.keys);
        }
        rethrow;
      }
      await _update(
        op,
        (record) => {
          ...record,
          'profile': profile,
          'pending': {..._pending(record)}
            ..removeWhere((k, _) => profilePatch.containsKey(k)),
        },
      );
    }

    if (pending.containsKey('farm_name')) {
      final Map<String, Object?> farm;
      try {
        farm = await _patch(op, '/account/farm', {
          'name': pending['farm_name'],
        });
      } on AuthException catch (e) {
        if (e.failure == AuthFailure.rejected ||
            e.failure == AuthFailure.gone) {
          await _drop(op, const ['farm_name']);
        }
        rethrow;
      }
      await _update(
        op,
        (record) => {
          ...record,
          'farm': farm,
          'pending': {..._pending(record)}..remove('farm_name'),
        },
      );
    }
  }

  Future<void> _drop(_Op op, Iterable<String> keys) => _update(
    op,
    (record) => {
      ...record,
      'pending': {..._pending(record)}..removeWhere((k, _) => keys.contains(k)),
    },
  );

  Future<Map<String, Object?>> _get(_Op op, String path) async =>
      _body(await _auth.authorized('GET', path, generation: op.generation));

  Future<Map<String, Object?>> _patch(
    _Op op,
    String path,
    Map<String, Object?> body,
  ) async => _body(
    await _auth.authorized(
      'PATCH',
      path,
      data: body,
      generation: op.generation,
    ),
  );

  Map<String, Object?> _body(Response<Object?> response) {
    throwUnlessSuccess(response);
    final data = response.data;
    if (data is Map) return data.cast<String, Object?>();
    throw const AuthException(AuthFailure.unknown);
  }

  /// What the screens see: the server's answer where there is one, the
  /// session's own copy of the user where there is not, and pending edits
  /// laid over both — the farmer sees what they typed, marked as waiting.
  AccountSnapshot _snapshot(AuthUser user, Map<String, Object?> record) {
    final profile = record['profile'] is Map
        ? (record['profile']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    final farm = record['farm'] is Map
        ? (record['farm']! as Map).cast<String, Object?>()
        : null;
    final pending = _pending(record);

    String text(String key, String fallback) =>
        (pending[key] ?? profile[key] ?? fallback).toString();

    return AccountSnapshot(
      userId: user.id,
      firstName: text('first_name', user.firstName),
      surname: text('surname', user.surname),
      phone: (profile['phone'] ?? user.phone).toString(),
      email: (profile['email'] ?? user.email).toString(),
      language: AppLanguage.fromCode(
        pending['preferred_language'] ?? profile['preferred_language'],
      ),
      farmName: (pending['farm_name'] ?? farm?['name']) as String?,
      consent: ConsentChoices.fromJson(record['consent']),
      hasPendingChanges: pending.isNotEmpty,
    );
  }
}

/// One account operation's identity: who it is for, and which session.
class _Op {
  final AuthUser user;
  final int generation;

  const _Op(this.user, this.generation);
}
