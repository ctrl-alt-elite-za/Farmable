/// Keeps a farm name chosen offline on the phone until the server has it,
/// and sends it as soon as there is a signal.
///
/// First farm setup saves the name as a pending account edit and writes it
/// onto the phone's copy of the farm. Two things would otherwise undo that:
///
/// * The sync controller re-reads `GET /farms` when the signal comes back
///   and overwrites the phone's farm row with the server's — still the
///   default name, because the pending edit has not been sent.
/// * Pending account edits are otherwise only sent at the next launch.
///
/// So whenever the account's farm on the phone changes — which includes that
/// re-read — this puts a still-pending name back, and, if the phone has a
/// network, sends the pending edits. Once the server accepts them the name
/// from its reply is written, and there is nothing pending left to keep.
///
/// Only a pending name, or the server's own reply to a send made here, is
/// ever written: never an older cached copy, which could undo a rename made
/// on another phone. Builds without the real API have no account farm, and
/// this does nothing there.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/setup/account_farm_name.dart';
import '../../data/setup/pending_farm_name.dart';

final farmNameKeeperProvider = Provider<void>((ref) {
  if (ref.watch(syncControllerProvider) == null) return;

  var running = false;
  var again = false;

  Future<void> once() async {
    final scope = ref.read(farmScopeProvider);
    if (!scope.isAccount) return;
    final db = ref.read(databaseProvider);
    final records = ref.read(accountStorageProvider);

    var pending = await pendingFarmName(records, scope.ownerId);
    if (pending == null) return;
    // Put it back first, so Home never shows the default in between.
    await nameAccountFarmLocally(db, scope, pending);

    if (!await ref.read(networkStatusProvider).current()) return;
    final account = ref.read(accountServiceProvider);
    await account.syncPending();
    if (ref.read(farmScopeProvider) != scope) return;

    pending = await pendingFarmName(records, scope.ownerId);
    if (pending != null) return; // Still not accepted; kept above.
    // Accepted: the server's reply is the freshest name there is.
    final sent = await account.cached();
    final name = sent?.farmName;
    if (sent == null || sent.userId != scope.ownerId || name == null) return;
    await nameAccountFarmLocally(db, scope, name);
  }

  Future<void> settle() async {
    if (running) {
      again = true;
      return;
    }
    running = true;
    try {
      do {
        again = false;
        try {
          await once();
        } on Object {
          // Tried again the next time the farm changes.
        }
      } while (again && ref.mounted);
    } finally {
      running = false;
    }
  }

  ref.listen(farmProvider, (_, next) {
    if (next.hasValue) unawaited(settle());
  }, fireImmediately: true);
});

/// Called from the app root's `build`, beside `keepFarmSynced`.
void keepFarmNameSent(WidgetRef ref) =>
    ref.listen(farmNameKeeperProvider, (_, _) {});
