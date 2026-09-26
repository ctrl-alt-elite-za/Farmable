/// Keeps a farm name chosen offline on the phone until the server has it,
/// and sends it when the signal comes back.
///
/// First farm setup saves the name as a pending account edit and writes it
/// onto the phone's copy of the farm. Two things would otherwise undo that:
///
/// * The sync controller re-reads `GET /farms` when the signal comes back
///   and overwrites the phone's farm row with the server's — still the
///   default name, because the pending edit has not been sent.
/// * Pending account edits are otherwise only sent at the next launch.
///
/// So when the farm's **name** on the phone changes to something this did
/// not write — which is what that re-read does — a still-pending name is put
/// back, and, with a network, the pending edits are sent. Other changes to
/// the farm (a record saved, a queued send moving on) do not wake it, and
/// neither do its own writes: one attempt per re-read, never a retry storm.
///
/// What it writes, and nothing else:
///
/// * the pending name, while it waits;
/// * nothing more once the server's reply carries that same name — the
///   phone already shows it;
/// * if the name was refused or the farm has gone, what the server calls the
///   farm now, read fresh from `GET /farms`. Never a cached copy: that could
///   be older than a rename made on another phone.
///
/// Builds without the real API have no account farm; this does nothing there.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../data/auth/api_auth_service.dart';
import '../../data/setup/account_farm_name.dart';
import '../../data/setup/pending_farm_name.dart';
import '../../data/setup/server_sections.dart';

final farmNameKeeperProvider = Provider<void>((ref) {
  if (ref.watch(syncControllerProvider) == null) return;

  /// The name this last put on the phone, so its own write is not mistaken
  /// for a re-read.
  String? written;
  var running = false;
  var again = false;

  Future<void> once() async {
    final scope = ref.read(farmScopeProvider);
    if (!scope.isAccount) return;
    final db = ref.read(databaseProvider);
    final records = ref.read(accountStorageProvider);
    bool current() => ref.mounted && ref.read(farmScopeProvider) == scope;
    Future<void> show(String name) async {
      written = name;
      await nameAccountFarmLocally(db, scope, name);
    }

    final pending = await pendingFarmName(records, scope.ownerId);
    if (pending == null) return;
    // Put it back first, so Home never shows the default in between.
    await show(pending);

    if (!await ref.read(networkStatusProvider).current()) return;
    await ref.read(accountServiceProvider).syncPending();
    if (!current()) return;

    // Still waiting — not sent, or edited again meanwhile: shown above.
    if (await pendingFarmName(records, scope.ownerId) != null) return;
    // Accepted: the server answered with this very name.
    if (await recordedFarmName(records, scope.ownerId) == pending) return;

    // Refused, or the farm is gone: put back what the server really has.
    final auth = ref.read(authServiceProvider);
    if (auth is! ApiAuthService) return;
    final actual = await serverFarmName(auth, scope.farmId);
    if (actual != null && current()) await show(actual);
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
          // Tried again the next time the farm is re-read.
        }
      } while (again && ref.mounted);
    } finally {
      running = false;
    }
  }

  ref.listen(farmProvider.select((farm) => farm.value?.farm.name), (_, name) {
    if (name == null || name == written) return;
    unawaited(settle());
  }, fireImmediately: true);
});

/// Called from the app root's `build`, beside `keepFarmSynced`.
void keepFarmNameSent(WidgetRef ref) =>
    ref.listen(farmNameKeeperProvider, (_, _) {});
