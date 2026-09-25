/// Puts the farm name the farmer just chose onto this phone's copy of their
/// account farm, so Home shows it straight away — with or without a signal.
///
/// The name itself goes to the server through `AccountService.updateDetails`
/// (`PATCH /account/farm`), which keeps it as a pending edit until it is
/// accepted. The phone's `farms` row is otherwise only written when the sync
/// controller reads `GET /farms`, which is why this exists: without it a
/// farmer who names their farm offline would see the server's default name
/// on Home until the next sign-in with a signal.
///
/// Only an account farm is ever renamed — the scope must be an account's and
/// the row must belong to it. The demo seed's name is never touched. No sync
/// mutation is queued: the account service is what sends the name, and the
/// next `GET /farms` settles the row to whatever the server holds.
library;

import 'package:drift/drift.dart';

import '../local/database.dart';
import '../sync/account_workspace.dart';

Future<void> nameAccountFarmLocally(
  AlmanacDatabase db,
  FarmScope scope,
  String name,
) async {
  if (!scope.isAccount) return;
  // Only when it differs: a write that changes nothing would still wake
  // everything watching the farm, including the keeper that calls this.
  await (db.update(db.farms)..where(
        (t) =>
            t.id.equals(scope.farmId) &
            t.ownerId.equals(scope.ownerId) &
            t.name.equals(name).not(),
      ))
      .write(FarmsCompanion(name: Value(name)));
}
