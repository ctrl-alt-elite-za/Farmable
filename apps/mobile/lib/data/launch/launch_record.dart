/// Whether this phone has been through the first-launch journey — brand
/// intro, onboarding, auth choice — so a later launch can go straight to Home.
///
/// Kept in a small JSON file of its own (`almanac_launch.json`, in the app's
/// documents directory) through the existing [FileSessionStorage], and
/// deliberately **not** in the farm database: it is a fact about this install,
/// not a farm record, and nothing about it is ever synced. Uninstalling the
/// app — or Maestro's `clearState` — removes it, which is exactly when the
/// journey should be shown again.
///
/// Every failure resolves towards Home. A launch that cannot tell whether the
/// intro was seen opens the farm, because the farm opening with no signal and
/// no login is the product's central promise, and the intro is not.
library;

import '../auth/session_storage.dart';

class LaunchRecord {
  LaunchRecord(this._storage, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// The file on a phone.
  LaunchRecord.onDevice()
    : this(FileSessionStorage(fileName: 'almanac_launch.json'));

  final SessionStorage _storage;
  final DateTime Function() _now;

  static const _seenKey = 'intro_seen_at';

  /// True once the journey has reached Auth Choice on this install.
  ///
  /// A record that is missing reads as "not yet": that is a fresh install.
  /// A read that throws reads as "seen": that is a phone we cannot trust to
  /// answer, and the safe place to land it is Home.
  Future<bool> introSeen() async {
    try {
      final record = await _storage.read();
      return record?[_seenKey] is String;
    } on Object {
      return true;
    }
  }

  /// Best effort. A write that fails means the journey shows once more on
  /// the next launch — a small cost, and never a reason to stop the farmer.
  Future<void> markIntroSeen() async {
    try {
      if (await introSeen()) return;
      await _storage.write({_seenKey: _now().toUtc().toIso8601String()});
    } on Object {
      // See above.
    }
  }
}
