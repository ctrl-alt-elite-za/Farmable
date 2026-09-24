/// The local demo [AccountService], paired with [DemoAuthService].
///
/// Everything stays on the phone: edits apply at once (there is no server to
/// be pending for), the export is a JSON file of what the phone holds about
/// the demo account, and deletion wipes the phone the same way the real one
/// does. What it does NOT do is check the password on deletion against
/// anything — the demo keeps only a salted digest in its own record, behind
/// its own service — so any non-empty password is accepted. Demo builds only.
library;

import 'dart:convert';

import '../../domain/account/account_models.dart';
import '../../domain/account/account_service.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/auth_service.dart';
import '../auth/session_storage.dart';
import '../device_wipe.dart';
import 'export_store.dart';

class DemoAccountService implements AccountService {
  final AuthService _auth;
  final SessionStorage _storage;
  final ExportStore _exports;
  final DeviceWipe _wipe;
  final DateTime Function() now;

  DemoAccountService(
    this._auth,
    this._storage,
    this._exports,
    this._wipe, {
    this.now = DateTime.now,
  });

  @override
  Future<AccountSnapshot?> cached() async {
    final user = await _user();
    if (user == null) return null;
    final record = await _record(user);
    final details = record['details'] is Map
        ? (record['details']! as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return AccountSnapshot(
      userId: user.id,
      firstName: (details['first_name'] ?? user.firstName).toString(),
      surname: (details['surname'] ?? user.surname).toString(),
      phone: user.phone,
      email: user.email,
      language: AppLanguage.fromCode(details['preferred_language']),
      farmName: (details['farm_name'] ?? 'My farm').toString(),
      consent: ConsentChoices.fromJson(record['consent']),
      hasPendingChanges: false,
    );
  }

  @override
  Future<AccountSnapshot?> refresh() => cached();

  @override
  Future<void> syncPending() async {}

  @override
  Future<AccountSnapshot> updateDetails({
    String? firstName,
    String? surname,
    AppLanguage? language,
    String? farmName,
  }) async {
    final user = await _requireUser();
    final record = await _record(user);
    final details = record['details'] is Map
        ? (record['details']! as Map).cast<String, Object?>()
        : <String, Object?>{};
    await _save(user, {
      ...record,
      'details': {
        ...details,
        if (firstName != null) 'first_name': firstName.trim(),
        if (surname != null) 'surname': surname.trim(),
        if (language != null) 'preferred_language': language.name,
        if (farmName != null) 'farm_name': farmName.trim(),
      },
    });
    return (await cached())!;
  }

  @override
  Future<AccountSnapshot> setConsent({required bool externalProcessing}) async {
    final user = await _requireUser();
    await _save(user, {
      ...await _record(user),
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
    if (file != null && file.isExpiredAt(now())) {
      await _exports.clear();
      return null;
    }
    return file;
  }

  /// JSON only: there is no archive library in the app, and the demo is not
  /// a reason to add one.
  @override
  Future<ExportFile> export(ExportFormat format) async {
    if (format != ExportFormat.json) {
      throw const AuthException(AuthFailure.notYetSupported);
    }
    final snapshot = await cached();
    if (snapshot == null) {
      throw const AuthException(AuthFailure.invalidSession);
    }
    final document = {
      'schema_version': 1,
      'demo': true,
      'account': {
        'first_name': snapshot.firstName,
        'surname': snapshot.surname,
        'phone': snapshot.phone,
        'email': snapshot.email,
        'preferred_language': snapshot.language.name,
      },
    };
    try {
      return await _exports.save(
        utf8.encode(jsonEncode(document)),
        format,
        now(),
      );
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
    if (password.isEmpty) throw const AuthException(AuthFailure.rejected);
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
      await _exports.clear();
    } on Object {
      // Stamped with its owner; never shown to anyone else.
    }
  }

  Future<AuthUser?> _user() async => switch (await _auth.restore()) {
    SignedIn(session: final session) => session.user,
    _ => null,
  };

  Future<AuthUser> _requireUser() async =>
      await _user() ?? (throw const AuthException(AuthFailure.invalidSession));

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
}
