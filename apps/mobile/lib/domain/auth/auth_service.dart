/// THE SEAM.
///
/// Everything the authentication screens can ask for, and nothing about how
/// it is answered. Two implementations ship:
///
/// * [ApiAuthService] in `data/auth/api_auth_service.dart` — the real one.
///   Calls the backend's `/auth/*` routes over `dio` and keeps the session in
///   platform secure storage (Keystore on Android, Keychain on iOS).
/// * [DemoAuthService] in `data/auth/demo_auth_service.dart` — entirely local,
///   completes every call without a network. Used by the widget tests, by
///   `DEMO_MODE` builds and by any build with no API configured.
///
/// Which one runs is decided in exactly one place: `demoAuthProvider` in
/// `app/providers.dart`. No screen, no view model and no test of a screen
/// names an implementation, so the screens behave the same over either.
///
/// The type vocabulary lines up with the backend's contract
/// (`packages/api-client/openapi.json`): `AuthUser` is its `UserResponse`, a
/// session carries its `expires_at`, and a [PendingSignup] carries the
/// `user_id` and `next_step` of its `AuthProgressResponse`.
library;

import 'auth_models.dart';

/// What a verification step produced.
sealed class VerificationResult {
  const VerificationResult();
}

/// One channel proved, another still owed.
class VerificationContinues extends VerificationResult {
  final PendingSignup next;

  const VerificationContinues(this.next);
}

/// Both channels proved. The account is live and this is its session.
class VerificationComplete extends VerificationResult {
  final AuthSession session;

  const VerificationComplete(this.session);
}

/// The narrow port the authentication feature is written against.
///
/// Every method either returns its result or throws [AuthException]. Nothing
/// here returns a nullable "it didn't work", because a silent null is exactly
/// how a failed login turns into a blank screen.
abstract class AuthService {
  /// Creates the account and sends the first code.
  ///
  /// [phone] arrives in full international form (`+27825550123`); composing
  /// it from the country code and the typed digits is the caller's job, so
  /// this port never has to know about dialling plans.
  Future<PendingSignup> signUp({
    required String firstName,
    required String surname,
    required String phone,
    required String email,
    required String password,
  });

  /// Proves one channel.
  ///
  /// [code] is never logged, never echoed into an exception and never put in
  /// a route parameter.
  Future<VerificationResult> verify({
    required String userId,
    required VerificationChannel channel,
    required String code,
  });

  /// Sends a fresh code, invalidating the one before it.
  Future<void> resendCode({
    required String userId,
    required VerificationChannel channel,
  });

  /// Email-or-phone plus password. No code is sent: issue #9 requires that a
  /// normal login never triggers an OTP.
  Future<AuthSession> logIn({
    required LoginMode mode,
    required String identifier,
    required String password,
  });

  /// Starts a password reset and sends a code.
  ///
  /// Returns nothing whether or not the account exists, for the same reason
  /// [AuthFailure.invalidCredentials] is coarse: the response must not reveal
  /// who has an account.
  Future<void> requestPasswordReset({
    required LoginMode mode,
    required String identifier,
  });

  /// Finishes a reset. Returns no session — guide §11 sends the farmer back
  /// to Login, so that the new password is used once before it is trusted.
  Future<void> resetPassword({
    required LoginMode mode,
    required String identifier,
    required String code,
    required String newPassword,
  });

  /// The session on this phone, if there is a usable one.
  ///
  /// Must not touch the network: this is what makes a cold launch in a field
  /// with no signal land on Home instead of on a spinner.
  Future<AuthStanding> restore();

  /// Extends the session if it is due, without ever blocking on the network.
  ///
  /// Returns where the farmer stands afterwards. A server that says the
  /// session is gone (revoked, expired, account deleted) signs the farmer out
  /// here — the session is dropped from the phone and [SignedOut] comes back.
  /// No signal is not a reason to sign anybody out: the session on the phone
  /// is returned unchanged and the next attempt tries again.
  Future<AuthStanding> refreshSession();

  /// Forgets the session. Never touches the farm database — the farmer's
  /// records are theirs whether or not they are signed in.
  Future<void> signOut();

  /// Gives up on the signup that is currently awaiting verification.
  ///
  /// The mirror image of [signOut], not a variant of it: sign-out keeps the
  /// account and drops the session, this drops the half-finished account and
  /// leaves every session alone. Its email and phone go back to being free,
  /// so someone who mistyped their number can sign up again with the same
  /// address instead of meeting [AuthFailure.accountExists] forever.
  ///
  /// Never removes an account that has completed verification, whatever the
  /// stored record claims is pending.
  Future<void> abandonSignup();
}
