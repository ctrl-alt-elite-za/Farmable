/// The account's state machine.
///
/// Holds the only path between "no account" and a stored session, so no widget
/// can mint, extend or fake one. Reads storage on build, which is what makes
/// reopening the app offline a read rather than a request.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/auth.dart';

class AuthController extends AsyncNotifier<AuthState> {
  /// Decides where the farmer stands, at launch, from storage alone where it
  /// can.
  ///
  /// The order matters. A session still inside its window returns *before*
  /// anything reaches for the network: issue #9 asks that a logged-in farmer
  /// can reopen the app with no internet, and a build that asked the server
  /// first would fail exactly when the requirement is being tested. Only an
  /// already-expired session is worth a request, because only then is there
  /// something the server can tell us that storage cannot.
  @override
  Future<AuthState> build() async {
    final store = ref.watch(sessionStoreProvider);
    final now = ref.watch(clockProvider)();

    final session = await store.readSession();
    if (session != null) {
      if (session.isValidAt(now)) return SignedIn(session);
      try {
        final renewed = await ref
            .read(authApiProvider)
            .refresh(session.refreshToken);
        await store.writeSession(renewed);
        return SignedIn(renewed);
      } on AuthException catch (error) {
        // Only the server saying "no" is grounds for discarding the token. An
        // unreachable API means we do not know, and throwing away the refresh
        // token on a bad signal would sign the farmer out permanently for
        // being offline at the wrong moment.
        if (error.failure == AuthFailure.invalidSession) {
          await store.clearSession();
        }
      }
    }

    final pending = await store.readPending();
    return pending == null ? const SignedOut() : AwaitingVerification(pending);
  }

  PendingSignup get _pending {
    final current = state.value;
    if (current is! AwaitingVerification) {
      throw const AuthException(AuthFailure.invalidSession);
    }
    return current.pending;
  }

  /// Runs [work], leaving the state it returns. A refusal restores the state
  /// the farmer was already in and rethrows, so a failed attempt never strands
  /// the UI in a loading spinner it cannot leave.
  Future<void> _attempt(Future<AuthState> Function() work) async {
    final previous = state.value ?? const SignedOut();
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await work());
    } on AuthException {
      state = AsyncValue.data(previous);
      rethrow;
    }
  }

  Future<void> signUp({
    required String firstName,
    required String surname,
    required String phone,
    required String email,
    required String password,
  }) => _attempt(() async {
    final pending = await ref
        .read(authApiProvider)
        .signUp(
          firstName: firstName,
          surname: surname,
          phone: phone,
          email: email,
          password: password,
        );
    // Persisted before anything else can go wrong. The server offers no way
    // to map an email back to a pending user_id, so losing this value strands
    // the farmer: re-registering answers `account_exists` and there is no
    // third option.
    await ref.read(sessionStoreProvider).writePending(pending);
    return AwaitingVerification(pending);
  });

  Future<void> verifyPhone(String code) => _attempt(() async {
    final next = await ref
        .read(authApiProvider)
        .verifyPhone(userId: _pending.userId, code: code);
    await ref.read(sessionStoreProvider).writePending(next);
    return AwaitingVerification(next);
  });

  Future<void> verifyEmail(String code) => _attempt(() async {
    final session = await ref
        .read(authApiProvider)
        .verifyEmail(userId: _pending.userId, code: code);
    return _keep(session);
  });

  Future<void> resend() async {
    final pending = _pending;
    await ref
        .read(authApiProvider)
        .resend(userId: pending.userId, channel: pending.nextStep);
  }

  Future<void> logIn({required String identifier, required String password}) =>
      _attempt(
        () async => _keep(
          await ref
              .read(authApiProvider)
              .logIn(identifier: identifier, password: password),
        ),
      );

  /// Stores a granted session and retires any half-finished signup, so a
  /// finished account can never be resumed back into verification.
  Future<AuthState> _keep(Session session) async {
    final store = ref.read(sessionStoreProvider);
    await store.writeSession(session);
    await store.clearPending();
    return SignedIn(session);
  }

  Future<void> signOut() async {
    final store = ref.read(sessionStoreProvider);
    await store.clearSession();
    await store.clearPending();
    state = const AsyncValue.data(SignedOut());
  }
}
