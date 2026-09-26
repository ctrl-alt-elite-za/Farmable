/// Offers first farm setup again when it is still owed — the setup gate could
/// not confirm the farm was empty (a weak signal right after sign-up), or the
/// app was closed part-way through setup.
///
/// It never holds a launch up: the app opens on Home as always, and this asks
/// the server in the background once the account's farm is showing, and again
/// whenever the signal comes back. Only when the server confirms the farm has
/// no sections, and the farmer is on Home, does it open `/setup/farm`. A farm
/// with sections — on the phone or on the server — settles it for good. No
/// answer leaves it owed for the next try.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/auth/api_auth_service.dart';
import '../../data/setup/server_sections.dart';
import 'setup_providers.dart';

class SetupResumer {
  SetupResumer(this._ref);

  final Ref _ref;

  /// Set by [keepSetupResumable]: where to open setup, and where the farmer is.
  GoRouter? router;

  bool _checking = false;

  Future<void> check() async {
    if (_checking) return;
    _checking = true;
    try {
      await _check();
    } on Object {
      // Tried again the next time the signal comes back or the app opens.
    } finally {
      _checking = false;
    }
  }

  Future<void> _check() async {
    final scope = _ref.read(farmScopeProvider);
    if (!scope.isAccount) return;
    final owed = _ref.read(setupOwedProvider);
    if (!await owed.owedTo(scope.ownerId, scope.farmId)) return;

    final farm = await _ref.read(farmProvider.future);
    if (farm != null &&
        farm.farm.id == scope.farmId &&
        farm.sections.isNotEmpty) {
      await owed.settle(scope.ownerId, scope.farmId);
      return;
    }
    final auth = _ref.read(authServiceProvider);
    if (auth is! ApiAuthService) return;
    final empty = await serverFarmHasNoSections(auth, scope.farmId);
    if (empty == null) return;
    if (!empty) {
      await owed.settle(scope.ownerId, scope.farmId);
      return;
    }

    // Confirmed empty. Only from Home: never pull the farmer out of a screen
    // they are using, or out of setup itself.
    if (_ref.read(farmScopeProvider) != scope) return;
    final router = this.router;
    if (router == null) return;
    if (router.routerDelegate.currentConfiguration.uri.path != '/home') return;
    router.go('/setup/farm');
  }
}

final setupResumerProvider = Provider<SetupResumer>((ref) {
  final resumer = SetupResumer(ref);
  if (ref.watch(syncControllerProvider) == null) return resumer;

  ref.listen(farmScopeProvider, (_, scope) {
    if (scope.isAccount) unawaited(resumer.check());
  }, fireImmediately: true);
  final signal = ref.watch(networkStatusProvider).changes.listen((online) {
    if (online) unawaited(resumer.check());
  });
  ref.onDispose(signal.cancel);
  return resumer;
});

/// Called from the app root's `build`, with the app's one router.
void keepSetupResumable(WidgetRef ref, GoRouter router) {
  ref.listen(setupResumerProvider, (_, _) {});
  ref.read(setupResumerProvider).router = router;
}
