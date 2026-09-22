/// Where the demo keeps what must survive a restart.
///
/// A port, not an implementation detail. The screens never see it; only
/// [DemoAuthService] does, and only through this interface — so when PR #51's
/// `SessionStore` over the platform keystore lands, the file implementation
/// below is deleted rather than migrated.
///
/// **This is not secure storage and does not pretend to be.** Issue #9
/// requires tokens in the platform keystore, and that is #51's `SessionStore`.
/// What is here is a JSON file in the app's private documents directory,
/// holding a demo session that grants access to nothing on any server. It
/// exists so that "log in, kill the app, reopen it, still signed in" can be
/// demonstrated and tested without a backend. See the seam notes in
/// `domain/auth/auth_service.dart`.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

abstract class SessionStorage {
  /// The whole record, or null if nothing has been written.
  Future<Map<String, Object?>?> read();

  Future<void> write(Map<String, Object?> value);

  Future<void> clear();
}

/// A JSON file in the app's own documents directory.
class FileSessionStorage implements SessionStorage {
  static const _fileName = 'almanac_demo_auth.json';

  File? _cached;

  Future<File> _file() async {
    final existing = _cached;
    if (existing != null) return existing;
    final dir = await getApplicationDocumentsDirectory();
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

  @override
  Future<void> write(Map<String, Object?> value) async {
    try {
      await (await _file()).writeAsString(jsonEncode(value), flush: true);
    } on Object {
      // Losing the session costs one login. Crashing costs the session and
      // whatever the farmer was doing.
    }
  }

  @override
  Future<void> clear() async {
    try {
      final file = await _file();
      if (file.existsSync()) await file.delete();
    } on Object {
      // Same reasoning as write.
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
