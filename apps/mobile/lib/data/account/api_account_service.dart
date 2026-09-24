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
    final user = await _signedInUser();
    if (user == null) return null;

    try {
      await _flush(user);
      final profile = await _get('/account/profile');
      Map<String, Object?>? farm;
      try {
        farm = await _get('/account/farm');
      } on AuthException catch (e) {
        // An account whose farm has gone still has a profile to show.
        if (e.failure != AuthFailure.gone) rethrow;
      }
      final record = await _record(user);
      await _save(user, {...record, 'profile': profile, 'farm': farm});
    } on AuthException catch (e) {
      if (e.failure != AuthFailure.offline) rethrow;
    }
    return cached();
  }

  @override
  Future<void> syncPending() async {
    final user = await _signedInUser();
    if (user == null) return;
    if (_pending(await _record(user)).isEmpty) return;
    try {
      await _flush(user);
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
    final user = await _requireUser();
    final record = await _record(user);
    await _save(user, {
      ...record,
      'pending': {
        ..._pending(record),
        if (firstName != null) 'first_name': firstName.trim(),
        if (surname != null) 'surname': surname.trim(),
        if (language != null) 'preferred_language': language.name,
        if (farmName != null) 'farm_name': farmName.trim(),
      },
    });

    try {
      await _flush(user);
    } on AuthException catch (e) {
      if (e.failure != AuthFailure.offline) rethrow;
    }
    return (await cached())!;
  }

  /// Kept on this phone only. The backend has no consent endpoint yet, so
  /// there is nothing to send it to — see `docs` in the #10 pull request.
  @override
  Future<AccountSnapshot> setConsent({required bool externalProcessing}) async {
    final user = await _requireUser();
    final record = await _record(user);
    await _save(user, {
      ...record,
      'consent': ConsentChoices(
        externalProcessing: externalProcessing,
        decidedAt: now().toUtc(),
      ).toJson(),
    });
    return (await cached())!;
  }

  @override
  Future<ExportFile?> currentExport() async {
    final file = await _exports.current();
    if (file == null) return null;
    if (file.isExpiredAt(now())) {
      await _exports.clear();
      return null;
    }
    return file;
  }

  @override
  Future<ExportFile> export(ExportFormat format) async {
    await _requireUser();
    final response = await _auth.authorized(
      'GET',
      '/account/export',
      query: {'format': format.name},
      responseType: ResponseType.bytes,
    );
    throwUnlessSuccess(response);
    final bytes = response.data;
    if (bytes is! List<int> || bytes.isEmpty) {
      throw const AuthException(AuthFailure.unknown);
    }
    try {
      return await _exports.save(bytes, format, now());
    } on Object {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
  }

  @override
  Future<void> removeExport() async {
    try {
      await _exports.clear();
    } on Object {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
  }

  @override
  Future<void> deleteAccount({required String password}) async {
    await _requireUser();
    final response = await _auth.authorized(
      'DELETE',
      '/account',
      data: {'password': password},
    );
    throwUnlessSuccess(response);

    // The account is gone on the server. Access on this phone ends now,
    // before the slower wipe starts.
    await _auth.endSessionLocally();
    // Past this point the account no longer exists, so the result is success
    // whatever the wipe manages: reporting a failure here would tell the
    // farmer nothing was deleted when their account is already gone.
    try {
      await _wipe.run();
    } on Object {
      // Each part of the wipe is independent; see DeviceWipe.
    }
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
      // As above, and it expires within a day regardless.
    }
  }

  // ------------------------------------------------------------------ guts

  Future<AuthUser?> _signedInUser() async => switch (await _auth.restore()) {
    SignedIn(session: final session) => session.user,
    _ => null,
  };

  Future<AuthUser> _requireUser() async =>
      await _signedInUser() ??
      (throw const AuthException(AuthFailure.invalidSession));

  /// The record, if it is this user's. Anyone else's reads as empty.
  Future<Map<String, Object?>> _record(AuthUser user) async {
    final record = await _storage.read();
    if (record == null || record['owner'] != user.id) return {};
    return record;
  }

  Future<void> _save(AuthUser user, Map<String, Object?> record) async {
    try {
      await _storage.write({...record, 'owner': user.id});
    } on SessionStorageException {
      throw const AuthException(AuthFailure.storageUnavailable);
    }
  }

  Map<String, Object?> _pending(Map<String, Object?> record) {
    final raw = record['pending'];
    return raw is Map ? raw.cast<String, Object?>() : {};
  }

  /// Sends pending edits, profile then farm. Each part is cleared from the
  /// pending set once the server accepts it; one the server rejects as
  /// invalid is cleared too — it will never be accepted — and the rejection
  /// is reported so the farmer knows their change did not land.
  Future<void> _flush(AuthUser user) async {
    var record = await _record(user);
    final pending = _pending(record);
    if (pending.isEmpty) return;

    final profilePatch = {
      for (final key in const ['first_name', 'surname', 'preferred_language'])
        if (pending.containsKey(key)) key: pending[key],
    };
    if (profilePatch.isNotEmpty) {
      final Map<String, Object?> profile;
      try {
        profile = await _patch('/account/profile', profilePatch);
      } on AuthException catch (e) {
        if (e.failure == AuthFailure.rejected) {
          await _drop(user, profilePatch.keys);
        }
        rethrow;
      }
      record = await _record(user);
      await _save(user, {
        ...record,
        'profile': profile,
        'pending': {..._pending(record)}
          ..removeWhere((k, _) => profilePatch.containsKey(k)),
      });
    }

    if (pending.containsKey('farm_name')) {
      final Map<String, Object?> farm;
      try {
        farm = await _patch('/account/farm', {'name': pending['farm_name']});
      } on AuthException catch (e) {
        if (e.failure == AuthFailure.rejected ||
            e.failure == AuthFailure.gone) {
          await _drop(user, const ['farm_name']);
        }
        rethrow;
      }
      record = await _record(user);
      await _save(user, {
        ...record,
        'farm': farm,
        'pending': {..._pending(record)}..remove('farm_name'),
      });
    }
  }

  Future<void> _drop(AuthUser user, Iterable<String> keys) async {
    final record = await _record(user);
    await _save(user, {
      ...record,
      'pending': {..._pending(record)}..removeWhere((k, _) => keys.contains(k)),
    });
  }

  Future<Map<String, Object?>> _get(String path) async =>
      _body(await _auth.authorized('GET', path));

  Future<Map<String, Object?>> _patch(
    String path,
    Map<String, Object?> body,
  ) async => _body(await _auth.authorized('PATCH', path, data: body));

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
