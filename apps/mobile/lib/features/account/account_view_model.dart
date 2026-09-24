/// The signed-in farmer's account, and every action the Profile screens take
/// on it.
///
/// Mirrors [AuthViewModel]: the screens read [accountViewModelProvider] and
/// call the methods here, and every action returns `Future<AuthFailure?>` —
/// null when it worked, the reason when it did not. Nothing throws at a
/// widget.
///
/// A server that says the session has ended (revoked elsewhere, account
/// deleted on another phone) is handed to [AuthViewModel.recheck], which lands
/// the farmer signed out. This view model then rebuilds to null.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/account/account_models.dart';
import '../../domain/account/account_service.dart';
import '../../domain/auth/auth_models.dart';
import '../auth/auth_view_model.dart';

class AccountViewModel extends AsyncNotifier<AccountSnapshot?> {
  AccountService get _service => ref.read(accountServiceProvider);

  /// The phone's copy at once, then the server's in the background.
  @override
  Future<AccountSnapshot?> build() async {
    final standing = await ref.watch(authViewModelProvider.future);
    if (standing is! SignedIn) return null;

    final cached = await ref.watch(accountServiceProvider).cached();
    unawaited(_refreshInBackground(cached));
    return cached;
  }

  Future<void> _refreshInBackground(AccountSnapshot? shown) async {
    try {
      final fresh = await _service.refresh();
      if (ref.mounted && identical(state.value, shown)) {
        state = AsyncData(fresh);
      }
    } on AuthException catch (e) {
      await _handle(e.failure);
    } on Object {
      // The phone's copy is still on screen, which is the right fallback.
    }
  }

  Future<AuthFailure?> updateDetails({
    String? firstName,
    String? surname,
    AppLanguage? language,
    String? farmName,
  }) => _attempt(() async {
    final next = await _service.updateDetails(
      firstName: firstName,
      surname: surname,
      language: language,
      farmName: farmName,
    );
    if (ref.mounted) state = AsyncData(next);
  });

  Future<AuthFailure?> setConsent({required bool externalProcessing}) =>
      _attempt(() async {
        final next = await _service.setConsent(
          externalProcessing: externalProcessing,
        );
        ref.invalidate(externalProcessingConsentProvider);
        if (ref.mounted) state = AsyncData(next);
      });

  /// Permanently deletes the account and wipes the phone.
  ///
  /// An unconfirmed outcome preserves the phone's data and session; a
  /// confirmed deletion reports whether cleanup finished. [password] goes
  /// to the service and nowhere else.
  Future<({AuthFailure? failure, DeletionOutcome? outcome})> deleteAccount({
    required String password,
  }) async {
    try {
      final outcome = await _service.deleteAccount(password: password);
      if (outcome == DeletionOutcome.unconfirmed) {
        return (failure: null, outcome: outcome);
      }
      ref.invalidate(externalProcessingConsentProvider);
      await ref.read(authViewModelProvider.notifier).recheck();
      return (failure: null, outcome: outcome);
    } on AuthException catch (e) {
      await _handle(e.failure);
      return (failure: e.failure, outcome: null);
    } on Object {
      return (failure: AuthFailure.unknown, outcome: null);
    }
  }

  Future<AuthFailure?> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } on AuthException catch (e) {
      await _handle(e.failure);
      return e.failure;
    } on Object {
      return AuthFailure.unknown;
    }
  }

  Future<void> _handle(AuthFailure failure) async {
    if (failure == AuthFailure.invalidSession && ref.mounted) {
      await ref.read(authViewModelProvider.notifier).recheck();
    } else if (failure == AuthFailure.rejected && ref.mounted) {
      // The rejected edit has been dropped; show what the account really is.
      state = AsyncData(await _service.cached());
    }
  }
}

final accountViewModelProvider =
    AsyncNotifierProvider<AccountViewModel, AccountSnapshot?>(
      AccountViewModel.new,
    );
