/// Where the farmer stands, and every action that changes it.
///
/// All of it. No auth screen calls [AuthService] directly, decides what a
/// failure means, or works out which step comes next — the screens read
/// [authViewModelProvider] and call the methods here, which is what keeps
/// `sign_up_screen.dart` and the rest layout and nothing else.
///
/// Every action returns `Future<AuthFailure?>`: null when it worked, and the
/// reason when it did not. Nothing throws at a widget, because an exception
/// crossing into `build` is how a failed login becomes a red screen.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/auth_service.dart';
import '../../domain/auth/contact_details.dart';

class AuthViewModel extends AsyncNotifier<AuthStanding> {
  AuthService get _service => ref.read(authServiceProvider);

  /// Reads the phone, never the network. This is what makes a cold launch on
  /// a dead signal land on Home rather than on a spinner.
  ///
  /// The session is extended afterwards, in the background — see
  /// [_refreshInBackground]. Nothing waits on it.
  @override
  Future<AuthStanding> build() async {
    final standing = await ref.watch(authServiceProvider).restore();
    if (standing is SignedIn) unawaited(_refreshInBackground(standing));
    return standing;
  }

  /// Extends the session if it is due, and signs the farmer out cleanly if the
  /// server says it has ended — revoked on another phone, or the account gone.
  ///
  /// Applied only if nothing else has changed the standing in the meantime:
  /// a farmer who taps Log out while this is in flight stays logged out.
  Future<void> _refreshInBackground(SignedIn launched) async {
    final AuthStanding next;
    try {
      next = await _service.refreshSession();
    } on Object {
      return;
    }
    if (!ref.mounted || !identical(state.value, launched)) return;
    final unchanged =
        next is SignedIn && next.session.token == launched.session.token;
    if (!unchanged) state = AsyncData(next);

    // Profile edits made offline go out at the first launch with a signal.
    // No network at all when there are none.
    if (next is SignedIn) {
      unawaited(ref.read(accountServiceProvider).syncPending());
    }
  }

  /// Re-reads where the farmer stands, refreshing the session if it is due.
  ///
  /// What an account screen calls after an authenticated request comes back
  /// [AuthFailure.invalidSession]: the service has already dropped the
  /// session, and this is how the screens find out.
  Future<void> recheck() async {
    final next = await _service.refreshSession();
    if (ref.mounted) state = AsyncData(next);
  }

  /// Creates the account and moves to phone verification.
  Future<AuthFailure?> signUp({
    required String firstName,
    required String surname,
    required DiallingCountry country,
    required String phone,
    required String email,
    required String password,
  }) => _attempt(() async {
    final pending = await _service.signUp(
      firstName: firstName,
      surname: surname,
      // Composed here rather than in the form, so the one place that knows a
      // South African 082 is an international 82 is the domain.
      phone: internationalPhone(country, phone),
      email: email,
      password: password,
    );
    state = AsyncData(AwaitingVerification(pending));
  });

  /// Proves the channel the flow is currently on.
  ///
  /// [code] is passed straight through and never stored, never put in the
  /// state, and never interpolated into a message.
  Future<AuthFailure?> submitCode(String code) {
    final pending = _pending;
    if (pending == null) return Future.value(AuthFailure.invalidSession);

    return _attempt(() async {
      final result = await _service.verify(
        userId: pending.userId,
        channel: pending.nextStep,
        code: code,
      );
      state = AsyncData(switch (result) {
        VerificationContinues(next: final next) => AwaitingVerification(next),
        VerificationComplete(session: final session) => SignedIn(session),
      });
    });
  }

  /// Sends a fresh code for the step the flow is on, invalidating the last.
  Future<AuthFailure?> resendCode() {
    final pending = _pending;
    if (pending == null) return Future.value(AuthFailure.invalidSession);
    return _attempt(
      () => _service.resendCode(
        userId: pending.userId,
        channel: pending.nextStep,
      ),
    );
  }

  /// Email-or-phone plus password. Sends no code: issue #9 requires that a
  /// normal login never triggers one.
  Future<AuthFailure?> logIn({
    required LoginMode mode,
    required DiallingCountry country,
    required String identifier,
    required String password,
  }) => _attempt(() async {
    final session = await _service.logIn(
      mode: mode,
      identifier: mode == LoginMode.phone
          ? internationalPhone(country, identifier)
          : identifier,
      password: password,
    );
    state = AsyncData(SignedIn(session));
  });

  Future<AuthFailure?> requestPasswordReset({
    required LoginMode mode,
    required DiallingCountry country,
    required String identifier,
  }) => _attempt(
    () => _service.requestPasswordReset(
      mode: mode,
      identifier: mode == LoginMode.phone
          ? internationalPhone(country, identifier)
          : identifier,
    ),
  );

  Future<AuthFailure?> resetPassword({
    required LoginMode mode,
    required DiallingCountry country,
    required String identifier,
    required String code,
    required String newPassword,
  }) => _attempt(
    () => _service.resetPassword(
      mode: mode,
      identifier: mode == LoginMode.phone
          ? internationalPhone(country, identifier)
          : identifier,
      code: code,
      newPassword: newPassword,
    ),
  );

  /// Forgets the session. The farm database is untouched — the records are
  /// the farmer's whether or not anybody is signed in.
  ///
  /// The account's details on this phone — profile, pending edits, privacy
  /// choices, any export — go with the session, so the next person to log in
  /// here never sees the last one's.
  Future<AuthFailure?> signOut() => _attempt(() async {
    await _service.signOut();
    await ref.read(accountServiceProvider).forget();
    state = const AsyncData(SignedOut());
  });

  /// Abandons a half-finished signup, so the verify screen can offer a way
  /// out that is not "reinstall the app".
  ///
  /// Not [signOut], which this used to delegate to. Sign-out drops the
  /// session and keeps the account, which on the verify screen meant the
  /// pending signup vanished while its unverified account stayed — and a
  /// farmer correcting a mistyped phone number then met "there is already an
  /// account with this email" with nothing left to try. Abandonment drops
  /// the unfinished account instead and leaves every session alone.
  Future<AuthFailure?> abandonSignup() => _attempt(() async {
    await _service.abandonSignup();
    // Read back rather than assuming: a verified account on the same phone
    // keeps its session, and only the record knows whether there is one.
    state = AsyncData(await _service.restore());
  });

  PendingSignup? get _pending => switch (state.value) {
    AwaitingVerification(pending: final pending) => pending,
    _ => null,
  };

  /// Runs [action], turning anything it throws into a reason.
  ///
  /// The catch-all is deliberate and the rethrow is deliberately absent: an
  /// unexpected exception here is still a failed attempt, and the farmer gets
  /// a sentence they can act on instead of a crash. Nothing is logged — the
  /// closure it wraps is holding a password.
  Future<AuthFailure?> _attempt(Future<void> Function() action) async {
    try {
      await action();
      return null;
    } on AuthException catch (e) {
      return e.failure;
    } on Object {
      return AuthFailure.unknown;
    }
  }
}

final authViewModelProvider =
    AsyncNotifierProvider<AuthViewModel, AuthStanding>(AuthViewModel.new);

/// Called from the app root's `build`, so the session is read — and, when it
/// is due, refreshed — however the app opens.
///
/// A cold launch lands on Home, and Home deliberately never reads the session;
/// without this, a farmer who only ever opens their farm would never have
/// their session extended and would find it lapsed the day they needed it. A
/// listener rather than a watch, so a change of standing never rebuilds the
/// app. Nothing waits on it: Home draws from local storage regardless.
void keepSessionFresh(WidgetRef ref) =>
    ref.listen(authViewModelProvider, (_, _) {});

/// What to tell the farmer, and what to do about it.
///
/// Every one of these is an instruction, not a diagnosis. "Check the password
/// and try again" beats "Authentication failed", and none of them uses the
/// words this product reserves for things that are actually broken.
String authAdvice(AuthFailure failure) => switch (failure) {
  AuthFailure.invalidCredentials =>
    'That email or phone and password do not go together. Check them and '
        'try again.',
  AuthFailure.accountExists =>
    'There is already an account with this email. Log in instead, or use '
        'another address.',
  AuthFailure.invalidVerification =>
    'That code is not the one we are expecting. Check the six digits, or ask '
        'for a new code.',
  AuthFailure.tooManyAttempts =>
    'Wait a minute before asking for another code.',
  AuthFailure.invalidSession =>
    'Start the sign-up again — this one has been closed.',
  // Not "try again": the same tap on a full phone fails the same way. The
  // instruction has to be the one that changes the outcome.
  AuthFailure.storageUnavailable =>
    'This phone could not save that. Free up some space and try again.',
  // Offline is not a failure in this product, so it does not get failure
  // language. It gets the one honest instruction: this particular step is the
  // one thing that needs a signal.
  AuthFailure.offline =>
    'This step needs a signal. Your saved farm still opens without one.',
  AuthFailure.rejected =>
    'Something in those details was not accepted. Check each one and try '
        'again.',
  AuthFailure.unavailable =>
    'Almanac could not do that just now. Try again in a few minutes — your '
        'saved farm still opens.',
  AuthFailure.notYetSupported =>
    'Resetting a password from the app is not ready yet. Your saved farm '
        'still opens without logging in.',
  AuthFailure.gone =>
    'That is no longer on your account. Go back and open it again.',
  AuthFailure.unknown => 'Try that once more.',
};
