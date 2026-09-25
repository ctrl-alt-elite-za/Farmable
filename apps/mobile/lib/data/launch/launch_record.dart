/// Whether this phone has been through the first-launch journey — brand
/// intro, onboarding, auth choice — so a later launch can go straight to Home.
///
/// Kept in a small JSON file of its own (`almanac_launch.json`, in the app's
/// documents directory), deliberately **not** in the farm database: it is a
/// fact about this install, not a farm record, and nothing about it is ever
/// synced. Uninstalling the app — or Maestro's `clearState` — removes it,
/// which is exactly when the journey should be shown again.
///
/// Every failure resolves towards Home. A launch that cannot tell whether the
/// intro was seen opens the farm, because the farm opening with no signal and
/// no login is the product's central promise, and the intro is not.
///
/// That is why this has its own [LaunchFile] rather than going through
/// `FileSessionStorage`: that one reads an unreadable or corrupt file as
/// "nothing there", which here would be a fresh install — and a phone whose
/// file cannot be read would then be shown the intro on every launch.
library;

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// The record's raw contents, told apart three ways: null for no file at all,
/// the text when it reads, and a throw when a file is there but cannot be read.
abstract interface class LaunchFile {
  Future<String?> read();

  Future<void> write(String contents);
}

/// `almanac_launch.json` in the app's documents directory.
class DeviceLaunchFile implements LaunchFile {
  DeviceLaunchFile({Future<Directory> Function()? directory})
    : _directory = directory ?? getApplicationDocumentsDirectory;

  final Future<Directory> Function() _directory;

  static const fileName = 'almanac_launch.json';

  Future<File> _file() async => File('${(await _directory()).path}/$fileName');

  /// Throws if the file exists and cannot be read. Only a file that is not
  /// there at all is null.
  @override
  Future<String?> read() async {
    final file = await _file();
    if (FileSystemEntity.typeSync(file.path) == FileSystemEntityType.notFound) {
      return null;
    }
    return file.readAsString();
  }

  /// Staged and renamed, so an interrupted write leaves no half-written file.
  @override
  Future<void> write(String contents) async {
    final file = await _file();
    final staged = File('${file.path}.tmp');
    await staged.writeAsString(contents, flush: true);
    await staged.rename(file.path);
  }
}

class LaunchRecord {
  LaunchRecord(this._file, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  /// The file on a phone.
  LaunchRecord.onDevice() : this(DeviceLaunchFile());

  final LaunchFile _file;
  final DateTime Function() _now;

  static const _seenKey = 'intro_seen_at';

  /// True once the journey has reached Auth Choice on this install.
  ///
  /// Only a record that is not there at all reads as "not yet": that is a
  /// fresh install. The file is only ever written to say "seen", so one that
  /// is there reads as seen however it reads — and one that cannot be read,
  /// or is garbled, is a phone we cannot trust to answer, and the safe place
  /// to land it is Home.
  Future<bool> introSeen() async {
    try {
      return await _file.read() != null;
    } on Object {
      return true;
    }
  }

  /// Best effort. A write that fails means the journey shows once more on
  /// the next launch — a small cost, and never a reason to stop the farmer.
  Future<void> markIntroSeen() async {
    try {
      if (await introSeen()) return;
      await _file.write(
        jsonEncode({_seenKey: _now().toUtc().toIso8601String()}),
      );
    } on Object {
      // See above.
    }
  }
}
