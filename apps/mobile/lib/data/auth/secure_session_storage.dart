/// Where the real session lives between launches: the platform keystore.
///
/// Android Keystore-backed encryption on Android, the Keychain on iOS — via
/// `flutter_secure_storage`. Issue #10 requires that tokens are stored there
/// and nowhere else, so nothing that holds an access or refresh token is ever
/// written to the documents directory, the farm database or a log.
///
/// The whole record is one JSON value under one key. The session and the
/// pending signup change together (verifying email clears the one and grants
/// the other), and one key means one write, so a phone that dies between the
/// two never restores a half-updated pair.
///
/// Excluded from Android Auto Backup (`res/xml/backup_rules.xml` and
/// `data_extraction_rules.xml`): a keystore key never leaves the phone it was
/// made on, so a restored copy of this record could only fail to decrypt.
library;

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'session_storage.dart';

class SecureSessionStorage implements SessionStorage {
  static const _key = 'almanac.session';

  final FlutterSecureStorage _storage;

  SecureSessionStorage({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            aOptions: AndroidOptions(storageNamespace: 'almanac_session'),
            iOptions: IOSOptions(
              // Readable once the phone has been unlocked since boot, and never
              // copied to another device in a backup or migration.
              accessibility: KeychainAccessibility.first_unlock_this_device,
            ),
          );

  /// Same rule as [FileSessionStorage.read]: a record that cannot be read is
  /// treated as absent. The farmer logs in again; they do not get an app that
  /// will not open. Deliberately not logged — the value holds tokens.
  @override
  Future<Map<String, Object?>?> read() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return null;
      final decoded = jsonDecode(raw);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on Object {
      return null;
    }
  }

  @override
  Future<void> write(Map<String, Object?> value) async {
    try {
      await _storage.write(key: _key, value: jsonEncode(value));
    } on Object {
      throw const SessionStorageException('write');
    }
  }

  @override
  Future<void> clear() async {
    try {
      await _storage.delete(key: _key);
    } on Object {
      throw const SessionStorageException('clear');
    }
  }
}
