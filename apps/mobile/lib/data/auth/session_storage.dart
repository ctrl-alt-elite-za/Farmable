/// Where a session record is kept between launches.
///
/// A port, not an implementation detail. The screens never see it; only the
/// [AuthService] implementations do, and only through this interface. Two
/// implementations ship: [SecureSessionStorage] (the platform keystore, for
/// the real API session) and [FileSessionStorage] below (the demo).
///
/// **[FileSessionStorage] is not secure storage and does not pretend to be.**
/// It is a JSON file in the app's private documents directory, holding a demo
/// session that grants access to nothing on any server. It is only ever
/// chosen alongside [DemoAuthService] — see `demoAuthProvider` in
/// `app/providers.dart` — and never holds a real token.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// A write or a clear that did not happen.
///
/// Read failures are deliberately not reported this way — see
/// [FileSessionStorage.read] for why launch is the one place that swallows.
class SessionStorageException implements Exception {
  /// What was being attempted, for a message that is not a stack trace.
  final String operation;

  const SessionStorageException(this.operation);

  /// Carries no part of the record, because the record holds a digest and a
  /// session token and this string reaches logs.
  @override
  String toString() => 'SessionStorageException($operation)';
}

abstract class SessionStorage {
  /// The whole record, or null if nothing has been written.
  Future<Map<String, Object?>?> read();

  Future<void> write(Map<String, Object?> value);

  Future<void> clear();
}

/// A JSON file in the app's own documents directory.
class FileSessionStorage implements SessionStorage {
  static const _fileName = 'almanac_demo_auth.json';

  /// Where the file lives. Defaults to the app's documents directory, and is
  /// injectable so a test can point it at a real directory it controls — the
  /// failure tests need a genuine [FileSessionStorage] over a path they can
  /// make unwritable, not a stand-in that only pretends to be one.
  final Future<Directory> Function() _directory;

  FileSessionStorage({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  File? _cached;

  Future<File> _file() async {
    final existing = _cached;
    if (existing != null) return existing;
    final dir = await _directory();
    return _cached = File('${dir.path}/$_fileName');
  }

  @override
  Future<Map<String, Object?>?> read() async {
    try {
      final file = await _file();
      if (!file.existsSync()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } on Object {
      // A half-written or hand-edited file is treated as absent rather than
      // thrown from. Launch is the one moment the app cannot afford to be
      // brittle: the alternative here is a farmer whose app will not open
      // until they reinstall it.
      return null;
    }
  }

  /// Writes the record whole, or not at all, and says which.
  ///
  /// Staged in a sibling file and renamed over the live one, so a write that
  /// is interrupted — by the phone dying mid-signup, which is the ordinary
  /// case this product is built for — leaves the previous record intact
  /// rather than a truncated file the next launch cannot read.
  ///
  /// Failure is thrown, not swallowed. Every caller is in the middle of
  /// telling the farmer something worked: a sign-out that did not persist is
  /// the previous session standing again on the next launch, which on a
  /// shared phone is someone else reading this farm's money.
  @override
  Future<void> write(Map<String, Object?> value) async {
    File? staged;
    try {
      final file = await _file();
      staged = File('${file.path}.tmp');
      await staged.writeAsString(jsonEncode(value), flush: true);
      await staged.rename(file.path);
    } on Object {
      // Best-effort tidy-up. The record that matters is the old one, and it
      // is still where it was.
      try {
        if (staged?.existsSync() ?? false) staged!.deleteSync();
      } on Object {
        // Nothing further to do, and nothing here may mask the real failure.
      }
      throw const SessionStorageException('write');
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } on Object {
      throw const SessionStorageException('clear');
    }
  }
}

/// Holds the record in memory. Used by the widget tests, and by any build that
/// should start every launch with a clean slate.
class InMemorySessionStorage implements SessionStorage {
  Map<String, Object?>? _value;

  InMemorySessionStorage([Map<String, Object?>? initial]) : _value = initial;

  @override
  Future<Map<String, Object?>?> read() async => _value;

  @override
  Future<void> write(Map<String, Object?> value) async => _value = value;

  @override
  Future<void> clear() async => _value = null;
}
