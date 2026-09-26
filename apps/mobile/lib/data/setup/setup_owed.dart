/// Whether first farm setup is still owed to an account on this phone.
///
/// Set when setup is opened, or when the setup gate could not confirm with
/// the server whether the farm is empty; cleared once the first section is
/// added, the farmer skips it, or the server says the farm has sections. So a
/// farmer who closes the app mid-setup, or signed up on a signal too weak for
/// the gate to ask, is offered setup again on a later launch rather than
/// never.
///
/// Kept in `almanac_setup_owed.json`, outside the farm database, and stamped
/// with the account and farm it is for — another account signing in on this
/// phone never inherits it. Every failure reads as "not owed": a phone that
/// cannot answer is never nagged.
library;

import 'dart:convert';

import '../launch/launch_record.dart';

class SetupOwed {
  SetupOwed(this._file);

  SetupOwed.onDevice()
    : this(DeviceLaunchFile(name: 'almanac_setup_owed.json'));

  final LaunchFile _file;

  Future<bool> owedTo(String userId, String farmId) async {
    try {
      final contents = await _file.read();
      if (contents == null) return false;
      final record = jsonDecode(contents);
      return record is Map &&
          record['user_id'] == userId &&
          record['farm_id'] == farmId &&
          record['owed'] == true;
    } on Object {
      return false;
    }
  }

  Future<void> owe(String userId, String farmId) =>
      _write(userId, farmId, true);

  Future<void> settle(String userId, String farmId) =>
      _write(userId, farmId, false);

  Future<void> _write(String userId, String farmId, bool owed) async {
    try {
      await _file.write(
        jsonEncode({'user_id': userId, 'farm_id': farmId, 'owed': owed}),
      );
    } on Object {
      // Best effort: the worst case is setup offered once more, or not again.
    }
  }
}
