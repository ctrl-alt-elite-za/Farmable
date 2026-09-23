/// THE SEAM.
///
/// Everything the authentication screens can ask for, and nothing about how
/// it is answered. One implementation ships today — [DemoAuthService] in
/// `data/auth/demo_auth_service.dart`, which is entirely local and completes
/// every call without a network. PR #51 builds the real thing: an `AuthApi`
/// over `dio` plus a `SessionStore` over the platform keystore.
///
/// ## Swapping the demo for the real implementation
///
/// Three things change and nothing else:
///
/// 1. Write `ApiAuthService implements AuthService`, delegating to #51's
///    `AuthApi` for the calls and its `SessionStore` for persistence. The
///    method bodies are close to one-liners; #51's `AuthController` already
///    performs each of these steps.
/// 2. Point `authServiceProvider` (in `app/providers.dart`) at it.
/// 3. Delete `DemoAuthService`, `SessionStorage`'s file implementation, and
///    the `demoAuth` flag in `app/config.dart`.
///
/// No screen, no view model and no test of a screen changes, because none of
/// them names an implementation. `test/support/auth_harness.dart` overrides
/// the same provider, so the widget tests keep working against whichever
/// implementation is wired in.
///
/// The type vocabulary here was chosen to line up with #51's `domain/auth.dart`
/// — `AuthUser`, a session with an `expiresAt` and an `isValidAt`, a
/// `PendingSignup` carrying `userId` and `nextStep`, and the same generic
/// `invalidCredentials` failure — so the adapter is a rename, not a redesign.
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
