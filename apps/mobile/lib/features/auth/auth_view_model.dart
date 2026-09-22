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

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../domain/auth/auth_models.dart';
import '../../domain/auth/auth_service.dart';
import '../../domain/auth/contact_details.dart';

class AuthViewModel extends AsyncNotifier<AuthStanding> {
  AuthService get _service => ref.read(authServiceProvider);

  /// Reads the phone, never the network. This is what makes a cold launch on
  /// a dead signal land on Home rather than on a spinner.
  @override
  Future<AuthStanding> build() => ref.watch(authServiceProvider).restore();

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
  Future<AuthFailure?> signOut() => _attempt(() async {
    await _service.signOut();
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
    'Creating an account needs a signal. Your saved farm still opens without '
        'one.',
  AuthFailure.unknown => 'Try that once more.',
};
