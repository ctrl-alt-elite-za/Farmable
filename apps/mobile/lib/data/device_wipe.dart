/// Returns the phone to the state of a fresh install, after the account has
/// been deleted.
///
/// Issue #10 requires that deletion "revokes local access immediately and
/// clears all on-device user caches". Everything the app keeps is listed
/// here, and each is cleared independently: a folder that will not delete
/// must not stop the session from being forgotten, and the session is cleared
/// first so that access ends before anything slower runs.
///
/// The farm database is emptied and the demo farm planted again — the same
/// state a new install opens on. Home works without an account, and must
/// still work the moment after an account stops existing.
library;

import 'dart:io';

import 'auth/session_storage.dart';
import 'local/database.dart';

class DeviceWipe {
  final AlmanacDatabase db;

  /// Session, account record, demo record — cleared first, in order.
  final List<SessionStorage> stores;

  /// Folders the app writes into: offline photos, exports.
  final List<Future<Directory> Function()> directories;

  /// Plants the demo farm back once the database is empty.
  final Future<void> Function() reseed;

  const DeviceWipe({
    required this.db,
    required this.stores,
    required this.directories,
    required this.reseed,
  });

  /// Attempts every part, whatever the others do, and returns whether all of
  /// them succeeded.
  Future<bool> run() async {
    var clean = true;

    for (final store in stores) {
      try {
        await store.clear();
      } on Object {
        clean = false; // Carried on regardless: see the library note.
      }
    }

    try {
      // Children before parents. `allTables` lists them in declaration
      // order - users and farms first - so reversed is a safe delete order
      // without switching foreign keys off.
      await db.transaction(() async {
        for (final table in db.allTables.toList().reversed) {
          await db.delete(table).go();
        }
      });
    } on Object {
      clean = false;
    }

    for (final directory in directories) {
      try {
        final dir = await directory();
        if (dir.existsSync()) await dir.delete(recursive: true);
      } on Object {
        clean = false;
      }
    }

    try {
      await reseed();
    } on Object {
      // Not a leftover of the account: Home plants its farm on the next
      // launch regardless, so this does not make the wipe incomplete.
    }
    return clean;
  }
}
