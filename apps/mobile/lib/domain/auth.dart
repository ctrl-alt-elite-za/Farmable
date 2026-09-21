/// The account, the session it grants, and the ways both can fail.
///
/// Kept free of Flutter and of `dio` so the rules can be asserted directly,
/// the same way [ObservationDraft] keeps the observation rules out of the form
/// widget. Nothing here knows how a session is stored or fetched.
library;

/// Which contact detail is being proven.
///
/// The server calls this a "channel" and orders them phone-then-email; the
/// order is the server's, not ours, and arrives in `next_step`.
enum VerificationChannel { phone, email }

/// Everything the server will tell us about the person signed in.
///
/// [phoneVerified] and [emailVerified] are carried even though a session only
/// exists when both are true, because they are what makes "unverified" a
/// readable state rather than an inference from a missing session.
class AuthUser {
  final String id;
  final String firstName;
  final String surname;
  final String phone;
  final String email;
  final bool phoneVerified;
  final bool emailVerified;

  const AuthUser({
    required this.id,
    required this.firstName,
    required this.surname,
    required this.phone,
    required this.email,
    required this.phoneVerified,
    required this.emailVerified,
  });

  String get fullName => '$firstName $surname';
}

/// A granted session.
///
/// [expiresAt] is the whole of the offline story: with no network there is no
/// way to ask the server whether a session still stands, so this field alone
/// decides. See [Session.isValidAt].
class Session {
  final String accessToken;
  final String refreshToken;
  final DateTime expiresAt;
  final AuthUser user;

  const Session({
    required this.accessToken,
    required this.refreshToken,
    required this.expiresAt,
    required this.user,
  });

  /// The offline validity rule, in one place so no caller can invent another.
  bool isValidAt(DateTime now) => expiresAt.isAfter(now);
}

/// A signup that has been created on the server but not finished.
///
/// This exists because the server offers no way back: every verify and resend
/// call needs the `user_id`, and nothing maps an email to a pending signup. A
/// phone that dies between creating the account and typing the first code
/// would otherwise strand the farmer — re-registering returns `account_exists`
/// and there is no third option.
class PendingSignup {
  final String userId;
  final VerificationChannel nextStep;

  const PendingSignup({required this.userId, required this.nextStep});
}

/// Why an authentication attempt did not succeed.
///
/// Deliberately coarser than the server's error codes in one specific place:
/// a wrong password and an unknown account both arrive as
/// [AuthFailure.invalidCredentials], because the server answers both with
/// `invalid_credentials` and pays the same Argon2 cost to do it. Splitting
/// them here would hand back the account-existence oracle the backend spends
/// a dummy hash to deny.
enum AuthFailure {
  invalidCredentials,
  accountExists,
  invalidVerification,
  otpRateLimited,
  invalidSession,
  verificationUnavailable,
  offline,
  unknown,
}

class AuthException implements Exception {
  final AuthFailure failure;

  const AuthException(this.failure);

  @override
  String toString() => 'AuthException(${failure.name})';
}

/// Where the farmer stands with their account.
sealed class AuthState {
  const AuthState();
}

/// No account on this phone, or one whose session has run out.
class SignedOut extends AuthState {
  const SignedOut();
}

/// An account exists on the server and still owes at least one code.
class AwaitingVerification extends AuthState {
  final PendingSignup pending;

  const AwaitingVerification(this.pending);
}

class SignedIn extends AuthState {
  final Session session;

  const SignedIn(this.session);
}
