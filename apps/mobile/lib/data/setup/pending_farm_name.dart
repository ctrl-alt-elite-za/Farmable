/// The farm name the farmer chose that the server has not accepted yet.
///
/// Read from the account record `ApiAccountService` keeps — its `pending`
/// edits, stamped with the account they belong to — and from nowhere else.
/// Only a name that is still waiting counts: the record's copy of the farm
/// may be older than a rename made on another phone, and correcting the
/// phone's farm to it would undo that rename.
library;

import '../auth/session_storage.dart';

Future<String?> pendingFarmName(
  SessionStorage accountRecord,
  String userId,
) async {
  try {
    final record = await accountRecord.read();
    if (record == null || record['owner'] != userId) return null;
    final pending = record['pending'];
    final name = pending is Map ? pending['farm_name'] : null;
    return name is String && name.trim().isNotEmpty ? name : null;
  } on Object {
    return null;
  }
}
